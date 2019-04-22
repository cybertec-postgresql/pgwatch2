package main

import (
	"context"
	"errors"
	"fmt"
	"go.etcd.io/etcd/client"
	"path"
	"strings"
	"time"
)

func ParseHostAndPortFromJdbcConnStr(connStr string) (string, string, error) {
	return "127.0.0.1", "5432", nil
}

func EtcdGetClusterMembers(database MonitoredDatabase) ([]PatroniClusterMember, error) {
	var ret []PatroniClusterMember
	//host_config:
	//dcs: etcd
	////master_only: true
	//scope: batman
	//namespace: /service/
	var endpoint string

	if database.Host == "" && database.Port == "" {
		return ret, errors.New("Missing ETCD connect info")
	}

	if strings.Contains(strings.ToLower(database.Host), "http") && strings.Contains(strings.ToLower(database.Host), ":")  {	// assume full endpoint given
		endpoint = database.Host
	} else if strings.Contains(database.Host, "http") && database.Port != "" {
		endpoint = fmt.Sprintf("%s:%s", database.Host, database.Port)
	} else {
		endpoint = fmt.Sprintf("http://%s:%s", database.Host, database.Port)
	}
	cfg := client.Config{
		Endpoints:               []string{endpoint},
		Transport:               client.DefaultTransport,
		HeaderTimeoutPerRequest: time.Second,
	}
	c, err := client.New(cfg)
	if err != nil {
		log.Error(err)
		return ret, err
	}
	kapi := client.NewKeysAPI(c)

	membersPath := path.Join(database.HostConfig.Namespace, database.HostConfig.Scope, "members")
	resp, err := kapi.Get(context.Background(), membersPath , &client.GetOptions{Recursive:true})
	if err != nil {
		log.Error("Could not read Patroni members from ETCD:", err)
		return ret, err
	}

	//log.Errorf("resp: %+v", resp)
	// print value
	for _, node := range resp.Node.Nodes {
		log.Errorf("value: %+v", node.Value)
		nodeData, err := jsonTextToStringMap(node.Value)
		if err != nil {
			log.Errorf("Could not parse ETCD node data for node \"%s\":", node, err)
			continue
		}
		role, _ := nodeData["role"]
		connUrl, _ := nodeData["conn_url"]

		ret = append(ret, PatroniClusterMember{Scope: database.HostConfig.Scope, ConnUrl: connUrl, Role: role})
	}
	return ret, nil
	//return []PatroniClusterMember{{Scope: "batman", ConnUrl: "postgres://127.0.0.1:5432/postgres", State: "active", Role: "master"}}, nil
}


func ResolveDatabasesFromPatroni(ce MonitoredDatabase) ([]MonitoredDatabase, error) {
	md := make([]MonitoredDatabase, 0)
	cm := make([]PatroniClusterMember, 0)
	var err error
	var dbUnique string

	log.Error("ce.HostConfig", ce.HostConfig)
	if ce.HostConfig.DcsType == DCS_TYPE_ETCD {
		cm, err = EtcdGetClusterMembers(ce)
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
		if ce.MasterOnly && m.Role != "master" {
			continue
		}
		host, port, err := ParseHostAndPortFromJdbcConnStr(m.ConnUrl)
		if err != nil {
			log.Error("Could not parse Patroni conn str \"%s\" [%s:%s]: %v", m.ConnUrl, ce.DBUniqueName, m.Scope, err)
		}
		if ce.MasterOnly {
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
				DBType:            "postgres"})
			continue
		} else {
			c, err := GetPostgresDBConnection("", ce.Host, ce.Port, "template1", ce.User, ce.Password,
				ce.SslMode, ce.SslRootCAPath, ce.SslClientCertPath, ce.SslClientKeyPath)
			if err != nil {
				return md, err
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
				return md, err
			}

			for _, d := range data {
				md = append(md, MonitoredDatabase{DBUniqueName: dbUnique + "_" + d["datname_escaped"].(string),
					DBName:            d["datname"].(string),
					Host:              ce.Host,
					Port:              ce.Port,
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
					DBType:            "postgres"})
			}
		}

	}

	return md, err
}
