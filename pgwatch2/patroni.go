package main

import (
	"context"
	"errors"
	"fmt"
	"go.etcd.io/etcd/client"
	"github.com/samuel/go-zookeeper/zk"
	"path"
	"regexp"
	"time"
)

func ParseHostAndPortFromJdbcConnStr(connStr string) (string, string, error) {
	r := regexp.MustCompile(`postgres://(.*)+:([0-9]+)/`)
	matches := r.FindStringSubmatch(connStr)
	if len(matches) != 3 {
		log.Errorf("Unexpected regex result groups:", matches)
		return "", "", errors.New(fmt.Sprintf("unexpected regex result groups: %v", matches))
	}
	return matches[1], matches[2], nil
}

func EtcdGetClusterMembers(database MonitoredDatabase) ([]PatroniClusterMember, error) {
	var ret []PatroniClusterMember

	if len(database.HostConfig.DcsEndpoints) == 0 {
		return ret, errors.New("Missing ETCD connect info, make sure host config has a 'dcs_endpoints' key")
	}

	cfg := client.Config{
		Endpoints:               database.HostConfig.DcsEndpoints,
		Transport:               client.DefaultTransport,
		HeaderTimeoutPerRequest: time.Second,
	}
	c, err := client.New(cfg)
	if err != nil {
		log.Error("Could not connect to DCS", err)
		return ret, err
	}
	kapi := client.NewKeysAPI(c)

	membersPath := path.Join(database.HostConfig.Namespace, database.HostConfig.Scope, "members")
	resp, err := kapi.Get(context.Background(), membersPath , &client.GetOptions{Recursive:true})
	if err != nil {
		log.Error("Could not read Patroni members from ETCD:", err)
		return ret, err
	}

	for _, node := range resp.Node.Nodes {
		log.Debugf("Found a cluster member from etcd: %+v", node.Value)
		nodeData, err := jsonTextToStringMap(node.Value)
		if err != nil {
			log.Errorf("Could not parse ETCD node data for node \"%s\": %s", node, err)
			continue
		}
		role, _ := nodeData["role"]
		connUrl, _ := nodeData["conn_url"]
		name := path.Base(node.Key)

		ret = append(ret, PatroniClusterMember{Scope: database.HostConfig.Scope, ConnUrl: connUrl, Role: role, Name: name})
	}
	return ret, nil
}


func ZookeeperGetClusterMembers(database MonitoredDatabase) ([]PatroniClusterMember, error) {
	var ret []PatroniClusterMember

	if len(database.HostConfig.DcsEndpoints) == 0 {
		return ret, errors.New("Missing Zookeeper connect info, make sure host config has a 'dcs_endpoints' key")
	}

	c, _, err := zk.Connect(database.HostConfig.DcsEndpoints, time.Second)
	if err != nil {
		log.Error("Could not connect to DCS", err)
		return ret, err
	}
	members, _, err := c.Children(path.Join(database.HostConfig.Namespace, database.HostConfig.Scope, "members"))
	if err != nil {
		log.Error("Could not read Patroni members from Zookeeper:", err)
		return ret, err
	}
	for _, member := range members {
		log.Debugf("Found a cluster member from Zookeeper: %+v", member)
		keyData, _, err := c.Get(path.Join(database.HostConfig.Namespace, database.HostConfig.Scope, "members", member))
		if err != nil {
			log.Errorf("Could not read member (%s) info from Zookeeper:", member, err)
			return ret, err
		}
		nodeData, err := jsonTextToStringMap(string(keyData))
		if err != nil {
			log.Errorf("Could not parse Zookeeper node data for node \"%s\": %s", member, err)
			continue
		}
		role, _ := nodeData["role"]
		connUrl, _ := nodeData["conn_url"]
		name := path.Base(member)

		ret = append(ret, PatroniClusterMember{Scope: database.HostConfig.Scope, ConnUrl: connUrl, Role: role, Name: name})
	}

	return ret, nil
}

func ResolveDatabasesFromPatroni(ce MonitoredDatabase) ([]MonitoredDatabase, error) {
	md := make([]MonitoredDatabase, 0)
	cm := make([]PatroniClusterMember, 0)
	var err error
	var dbUnique string

	log.Error("ce.HostConfig", ce.HostConfig)
	if ce.HostConfig.DcsType == DCS_TYPE_ETCD {
		cm, err = EtcdGetClusterMembers(ce)
	} else if ce.HostConfig.DcsType == DCS_TYPE_ZOOKEEPER{
		cm, err = ZookeeperGetClusterMembers(ce)
	} else {
		log.Error("unknown DCS", ce.HostConfig.DcsType)
		return md, errors.New("unknown DCS")
	}
	if len(cm) == 0 {
		log.Warningf("No Patroni cluster members found for cluster [%s:%s]", ce.DBUniqueName, ce.HostConfig.Scope)
		return md, nil
	}
	log.Infof("Found %d Patroni members for cluster [%s:%s]", len(cm), ce.DBUniqueName, ce.HostConfig.Scope)

	for _, m := range cm {
		log.Infof("Processing Patroni cluster member [%s:%s]", ce.DBUniqueName, m.Name)
		if ce.OnlyIfMaster && m.Role != "master" {
			log.Infof("Skipping over Patroni cluster member [%s:%s] as not a master", ce.DBUniqueName, m.Name)
			continue
		}
		host, port, err := ParseHostAndPortFromJdbcConnStr(m.ConnUrl)
		if err != nil {
			log.Errorf("Could not parse Patroni conn str \"%s\" [%s:%s]: %v", m.ConnUrl, ce.DBUniqueName, m.Scope, err)
			continue
		}
		if ce.OnlyIfMaster {
			dbUnique = ce.DBUniqueName
		} else {
			dbUnique = ce.DBUniqueName + "_" + m.Name
		}
		if ce.DBName != "" {
			md = append(md, MonitoredDatabase{DBUniqueName: dbUnique,
				DBName:            ce.DBName,
				Host:              host,
				Port:              port,
				User:              ce.User,
				Password:          ce.Password,
				PasswordType:      ce.PasswordType,
				SslMode:           ce.SslMode,
				SslRootCAPath:     ce.SslRootCAPath,
				SslClientCertPath: ce.SslClientCertPath,
				SslClientKeyPath:  ce.SslClientKeyPath,
				StmtTimeout:       ce.StmtTimeout,
				Metrics:           ce.Metrics,
				PresetMetrics:     ce.PresetMetrics,
				IsSuperuser:       ce.IsSuperuser,
				CustomTags:        ce.CustomTags,
				HostConfig:	       ce.HostConfig,
				DBType:            "postgres"})
			continue
		} else {
			c, err := GetPostgresDBConnection("", host, port, "template1", ce.User, ce.Password,
				ce.SslMode, ce.SslRootCAPath, ce.SslClientCertPath, ce.SslClientKeyPath)
			if err != nil {
				log.Errorf("Could not contact Patroni member [%s:%s]: %v", ce.DBUniqueName, m.Scope, err)
				continue
			}
			defer c.Close()
			sql := `select datname::text as datname,
					quote_ident(datname)::text as datname_escaped
					from pg_database
					where not datistemplate
					and datallowconn
					and has_database_privilege (datname, 'CONNECT')
					and case when length(trim($1)) > 0 then datname ~ $2 else true end
					and case when length(trim($3)) > 0 then not datname ~ $4 else true end`

			data, err := DBExecRead(c, ce.DBUniqueName, sql, ce.DBNameIncludePattern, ce.DBNameIncludePattern, ce.DBNameExcludePattern, ce.DBNameExcludePattern)
			if err != nil {
				log.Errorf("Could not get DB name listing from Patroni member [%s:%s]: %v", ce.DBUniqueName, m.Scope, err)
				continue
			}

			for _, d := range data {
				md = append(md, MonitoredDatabase{DBUniqueName: dbUnique + "_" + d["datname_escaped"].(string),
					DBName:            d["datname"].(string),
					Host:              host,
					Port:              port,
					User:              ce.User,
					Password:          ce.Password,
					PasswordType:      ce.PasswordType,
					SslMode:           ce.SslMode,
					SslRootCAPath:     ce.SslRootCAPath,
					SslClientCertPath: ce.SslClientCertPath,
					SslClientKeyPath:  ce.SslClientKeyPath,
					StmtTimeout:       ce.StmtTimeout,
					Metrics:           ce.Metrics,
					PresetMetrics:     ce.PresetMetrics,
					IsSuperuser:       ce.IsSuperuser,
					CustomTags:        ce.CustomTags,
					HostConfig:        ce.HostConfig,
					DBType:            "postgres"})
			}
		}

	}

	return md, err
}

