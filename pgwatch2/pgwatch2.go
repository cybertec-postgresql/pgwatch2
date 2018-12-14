package main

import (
	"container/list"
	go_sql "database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/ioutil"
	"math"
	"net"
	"net/http"
	"os"
	"path"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/coreos/go-systemd/daemon"
	"github.com/influxdata/influxdb/client/v2"
	"github.com/jessevdk/go-flags"
	"github.com/jmoiron/sqlx"
	_ "github.com/lib/pq"
	"github.com/marpaia/graphite-golang"
	"github.com/op/go-logging"
	"github.com/shopspring/decimal"
	yaml "gopkg.in/yaml.v2"
)

type MonitoredDatabase struct {
	DBUniqueName         string `yaml:"unique_name"`
	Group                string
	Host                 string
	Port                 string
	DBName               string
	User                 string
	Password             string
	SslMode              string
	Metrics              map[string]float64 `yaml:"custom_metrics"`
	StmtTimeout          int64
	DBType               string
	DBNameIncludePattern string            `yaml:"dbname_include_pattern"`
	DBNameExcludePattern string            `yaml:"dbname_exclude_pattern"`
	PresetMetrics        string            `yaml:"preset_metrics"`
	IsSuperuser          bool              `yaml:"is_superuser"`
	IsEnabled            bool              `yaml:"is_enabled"`
	CustomTags           map[string]string `yaml:"custom_tags"` // ignored on graphite
}

type PresetConfig struct {
	Name        string
	Description string
	Metrics     map[string]float64
}

type ControlMessage struct {
	Action string // START, STOP, PAUSE
	Config map[string]float64
}

type MetricFetchMessage struct {
	DBUniqueName string
	MetricName   string
	DBType       string
	Interval     time.Duration
	CreatedOn    time.Time
}

type MetricStoreMessage struct {
	DBUniqueName string
	DBType       string
	MetricName   string
	CustomTags   map[string]string
	Data         [](map[string]interface{})
}

type ChangeDetectionResults struct { // for passing around DDL/index/config change detection results
	Created int
	Altered int
	Dropped int
}

type DBVersionMapEntry struct {
	LastCheckedOn time.Time
	IsInRecovery  bool
	Version       decimal.Decimal
}

const EPOCH_COLUMN_NAME string = "epoch_ns"      // this column (epoch in nanoseconds) is expected in every metric query
const METRIC_DEFINITION_REFRESH_TIME int64 = 120 // min time before checking for new/changed metric definitions
const ACTIVE_SERVERS_REFRESH_TIME int64 = 60     // min time before checking for new/changed databases under monitoring i.e. main loop time
const GRAPHITE_METRICS_PREFIX string = "pgwatch2"
const PERSIST_QUEUE_MAX_SIZE = 100000 // storage queue max elements. when reaching the limit, older metrics will be dropped.
// actual requirements depend a lot of metric type and nr. of obects in schemas,
// but 100k should be enough for 24h, assuming 5 hosts monitored with "exhaustive" preset config. this would also require ~2 GB RAM per one Influx host
const DATASTORE_INFLUX = "influx"
const DATASTORE_GRAPHITE = "graphite"
const DATASTORE_JSON = "json"
const PRESET_CONFIG_YAML_FILE = "preset-configs.yaml"
const FILE_BASED_METRIC_HELPERS_DIR = "00_helpers"
const PG_CONN_RECYCLE_SECONDS = 1800                // applies for monitored nodes
const APPLICATION_NAME = "pgwatch2"                 // will be set on all opened PG connections for informative purposes
const TABLE_BLOAT_APPROX_TIMEOUT_MIN_SECONDS = 1800 // special statement timeout override for pgstatuple_approx metrics as they can be slow (seq. scans)
const MAX_PG_CONNECTIONS_PER_MONITORED_DB = 2       // for limiting max concurrent queries on a single DB, sql.DB maxPoolSize cannot be fully trusted
const GATHERER_STATUS_START = "START"
const GATHERER_STATUS_STOP = "STOP"

var configDb *sqlx.DB
var graphiteConnection *graphite.Graphite
var log = logging.MustGetLogger("main")
var metric_def_map map[string]map[decimal.Decimal]string
var metric_def_map_lock = sync.RWMutex{}
var host_metric_interval_map = make(map[string]float64) // [db1_metric] = 30
var db_pg_version_map = make(map[string]DBVersionMapEntry)
var db_pg_version_map_lock = sync.RWMutex{}
var InfluxDefaultRetentionPolicyDuration int64 = 30 // 30 days of monitoring data will be kept around. can be adjusted later on influx side if needed
var monitored_db_cache map[string]MonitoredDatabase
var monitored_db_cache_lock sync.RWMutex
var monitored_db_conn_cache map[string]*sqlx.DB = make(map[string]*sqlx.DB)
var monitored_db_conn_cache_lock = sync.RWMutex{}
var db_conn_limiting_channel = make(map[string](chan bool))
var db_conn_limiting_channel_lock = sync.RWMutex{}
var last_sql_fetch_error sync.Map
var influx_host_count = 1
var InfluxConnectStrings [2]string // Max. 2 Influx metrics stores currently supported
// secondary Influx meant for HA or Grafana load balancing for 100+ instances with lots of alerts
var fileBased = false
var adHocMode = false
var continuousMonitoringDatabases = make([]MonitoredDatabase, 0) // TODO
var preset_metric_def_map map[string]map[string]float64          // read from metrics folder in "file mode"
/// internal statistics calculation
var lastSuccessfulDatastoreWriteTime time.Time
var totalMetricsFetchedCounter uint64
var totalMetricsDroppedCounter uint64
var totalDatasetsFetchedCounter uint64
var metricPointsPerMinuteLast5MinAvg int64 = -1 // -1 means the summarization ticker has not yet run
var gathererStartTime time.Time = time.Now()
var useConnPooling bool

func GetPostgresDBConnection(libPgConnString, host, port, dbname, user, password, sslmode string) (*sqlx.DB, error) {
	var err error
	var db *sqlx.DB

	//log.Debug("Connecting to: ", host, port, dbname, user, password)
	if len(libPgConnString) > 0 {
		if strings.Contains(strings.ToLower(libPgConnString), "sslmode=") {
			db, err = sqlx.Open("postgres", libPgConnString)
		} else {
			if strings.Contains(libPgConnString, "?") { // a bit simplistic, regex would be better
				log.Debug("Adding sslmode", libPgConnString+"&sslmode=disable")
				db, err = sqlx.Open("postgres", libPgConnString+"&sslmode=disable")
			} else {
				log.Debug("Adding sslmode", libPgConnString+"?sslmode=disable")
				db, err = sqlx.Open("postgres", libPgConnString+"?sslmode=disable")
			}
		}
	} else {
		db, err = sqlx.Open("postgres", fmt.Sprintf("host=%s port=%s dbname=%s sslmode=%s user=%s password=%s application_name=%s",
			host, port, dbname, sslmode, user, password, APPLICATION_NAME))
	}

	if err != nil {
		log.Error("could not open Postgres connection", err)
	}
	return db, err
}

func StringToBoolOrFail(boolAsString string) bool {
	conversionMap := map[string]bool{
		"true": true, "t": true, "on": true, "y": true, "yes": true, "require": true, "1": true,
		"false": false, "f": false, "off": false, "n": false, "no": false, "disable": false, "0": false,
	}
	val, ok := conversionMap[strings.TrimSpace(strings.ToLower(boolAsString))]
	if !ok {
		log.Fatalf("invalid input for boolean: %s", boolAsString)
	}
	return val
}

func InitAndTestConfigStoreConnection(host, port, dbname, user, password, requireSSL string) {
	var err error
	SSLMode := "disable"

	if StringToBoolOrFail(requireSSL) {
		SSLMode = "require"
	}
	configDb, err = GetPostgresDBConnection("", host, port, dbname, user, password, SSLMode) // configDb is used by the main thread only
	if err != nil {
		log.Fatal("could not open configDb connection! exit.")
	}

	err = configDb.Ping()

	if err != nil {
		log.Fatal("could not ping configDb! exit.", err)
	} else {
		log.Info("connect to configDb OK!")
	}
	configDb.SetMaxIdleConns(1)
	configDb.SetMaxOpenConns(2)
	configDb.SetConnMaxLifetime(time.Second * time.Duration(PG_CONN_RECYCLE_SECONDS))
}

func DBExecRead(conn *sqlx.DB, host_ident, sql string, args ...interface{}) ([](map[string]interface{}), error) {
	ret := make([]map[string]interface{}, 0)
	var rows *sqlx.Rows
	var err error

	rows, err = conn.Queryx(sql, args...)

	if err != nil {
		conn.Close()
		monitored_db_conn_cache_lock.Lock()
		defer monitored_db_conn_cache_lock.Unlock()
		if _, ok := monitored_db_conn_cache[host_ident]; ok {
			monitored_db_conn_cache[host_ident] = nil
		}
		// connection problems or bad queries etc are quite common so caller should decide if to output something
		log.Debug("failed to query", host_ident, "sql:", sql, "err:", err)
		return nil, err
	}
	defer rows.Close()

	for rows.Next() {
		row := make(map[string]interface{})
		err = rows.MapScan(row)
		if err != nil {
			log.Error("failed to MapScan a result row", host_ident, err)
			return nil, err
		}
		ret = append(ret, row)
	}

	err = rows.Err()
	if err != nil {
		log.Error("failed to fully process resultset for", host_ident, "sql:", sql, "err:", err)
	}
	return ret, err
}

func DBExecReadByDbUniqueName(dbUnique, metricName string, useCache bool, sql string, args ...interface{}) ([](map[string]interface{}), error, time.Duration) {
	var conn *sqlx.DB
	var exists bool
	var md MonitoredDatabase
	var err error
	var duration time.Duration

	if strings.TrimSpace(sql) == "" {
		return nil, errors.New("empty SQL"), duration
	}

	md, err = GetMonitoredDatabaseByUniqueName(dbUnique)
	if err != nil {
		return nil, err, duration
	}

	db_conn_limiting_channel_lock.RLock()
	conn_limit_channel, ok := db_conn_limiting_channel[dbUnique]
	db_conn_limiting_channel_lock.RUnlock()
	if !ok {
		log.Fatal("db_conn_limiting_channel not initialized for ", dbUnique)
	}

	//log.Debugf("Waiting for SQL token [%s:%s]...", msg.DBUniqueName, msg.MetricName)
	token := <-conn_limit_channel
	defer func() {
		conn_limit_channel <- token
	}()

	if !useCache {
		if md.DBType == "pgbouncer" {
			md.DBName = "pgbouncer"
		}

		conn, err = GetPostgresDBConnection(opts.AdHocConnString, md.Host, md.Port, md.DBName, md.User, md.Password, md.SslMode)
		if err != nil {
			return nil, err, duration
		}
		defer conn.Close()

		if !adHocMode && md.DBType == "postgres" {
			stmtTimeout := md.StmtTimeout
			if (metricName == "table_bloat_approx_summary" || metricName == "table_bloat_approx_stattuple") && md.StmtTimeout < TABLE_BLOAT_APPROX_TIMEOUT_MIN_SECONDS {
				stmtTimeout = TABLE_BLOAT_APPROX_TIMEOUT_MIN_SECONDS
			}
			_, err = DBExecRead(conn, dbUnique, fmt.Sprintf("SET statement_timeout TO '%ds'", stmtTimeout))
			if err != nil {
				return nil, err, duration
			}
		}
	} else {
		var dbStats go_sql.DBStats
		monitored_db_conn_cache_lock.RLock()
		conn, exists = monitored_db_conn_cache[dbUnique]
		monitored_db_conn_cache_lock.RUnlock()
		if conn != nil {
			dbStats = conn.Stats()
		}

		if !exists || conn == nil || dbStats.OpenConnections == 0 {

			if md.DBType == "pgbouncer" {
				md.DBName = "pgbouncer"
			}

			conn, err = GetPostgresDBConnection(opts.AdHocConnString, md.Host, md.Port, md.DBName, md.User, md.Password, md.SslMode)
			if err != nil {
				return nil, err, duration
			}
			if !adHocMode && md.DBType == "postgres" {
				log.Debugf("Setting statement_timeout to %ds for the new PG connection to %s...", md.StmtTimeout, dbUnique)
				_, err = DBExecRead(conn, dbUnique, fmt.Sprintf("SET statement_timeout TO '%ds'", md.StmtTimeout))
				if err != nil {
					return nil, err, duration
				}
			}

			conn.SetMaxIdleConns(1)
			conn.SetMaxOpenConns(MAX_PG_CONNECTIONS_PER_MONITORED_DB)
			// recycling periodically makes sense as long sessions might bloat memory or maybe conn info (password) was changed
			conn.SetConnMaxLifetime(time.Second * time.Duration(PG_CONN_RECYCLE_SECONDS))

			monitored_db_conn_cache_lock.Lock()
			monitored_db_conn_cache[dbUnique] = conn
			monitored_db_conn_cache_lock.Unlock()
		}

		// special override for possibly long running bloat queries
		if md.DBType == "postgres" && (metricName == "table_bloat_approx_summary" || metricName == "table_bloat_approx_stattuple") && md.StmtTimeout < TABLE_BLOAT_APPROX_TIMEOUT_MIN_SECONDS {
			_, err = DBExecRead(conn, dbUnique, fmt.Sprintf("SET statement_timeout TO '%ds'", TABLE_BLOAT_APPROX_TIMEOUT_MIN_SECONDS))
			if err != nil {
				return nil, err, duration
			}
		}
	}
	t1 := time.Now()
	data, err := DBExecRead(conn, dbUnique, sql, args...)
	t2 := time.Now()

	if err == nil && md.DBType == "postgres" && useCache && (metricName == "table_bloat_approx_summary" || metricName == "table_bloat_approx_stattuple") {
		// restore general statement timeout
		_, err = DBExecRead(conn, dbUnique, fmt.Sprintf("SET statement_timeout TO '%ds'", md.StmtTimeout))
		if err != nil {
			return nil, err, t2.Sub(t1)
		}
	}

	return data, err, t2.Sub(t1)
}

func GetAllActiveHostsFromConfigDB() ([](map[string]interface{}), error) {
	sql := `
		select
		  md_unique_name, md_group, md_dbtype, md_hostname, md_port, md_dbname, md_user, coalesce(md_password, '') as md_password,
		  coalesce(pc_config, md_config)::text as md_config, md_statement_timeout_seconds, md_sslmode, md_is_superuser,
		  coalesce(md_include_pattern, '') as md_include_pattern, coalesce(md_exclude_pattern, '') as md_exclude_pattern,
		  coalesce(md_custom_tags::text, '{}') as md_custom_tags
		from
		  pgwatch2.monitored_db
	          left join
		  pgwatch2.preset_config on pc_name = md_preset_config_name
		where
		  md_is_enabled
	`
	data, err := DBExecRead(configDb, "configDb", sql)
	if err != nil {
		log.Error(err)
	}
	return data, err
}

func GetMonitoredDatabasesFromConfigDB() ([]MonitoredDatabase, error) {
	monitoredDBs := make([]MonitoredDatabase, 0)
	activeHostData, err := GetAllActiveHostsFromConfigDB()
	groups := strings.Split(opts.Group, ",")
	skippedEntries := 0

	if err != nil {
		log.Errorf("Failed to read monitoring config from DB: %s", err)
		return monitoredDBs, err
	}

	for _, row := range activeHostData {

		if len(opts.Group) > 0 { // filter out rows with non-matching groups
			matched := false
			for _, g := range groups {
				if row["md_group"].(string) == g {
					matched = true
					break
				}
			}
			if !matched {
				skippedEntries += 1
				continue
			}
		}
		if skippedEntries > 0 {
			log.Infof("Filtered out %d config entries based on --groups input", skippedEntries)
		}

		md := MonitoredDatabase{
			DBUniqueName:         row["md_unique_name"].(string),
			Host:                 row["md_hostname"].(string),
			Port:                 row["md_port"].(string),
			DBName:               row["md_dbname"].(string),
			User:                 row["md_user"].(string),
			Password:             row["md_password"].(string),
			SslMode:              row["md_sslmode"].(string),
			StmtTimeout:          row["md_statement_timeout_seconds"].(int64),
			Metrics:              jsonTextToMap(row["md_config"].(string)),
			DBType:               row["md_dbtype"].(string),
			DBNameIncludePattern: row["md_include_pattern"].(string),
			DBNameExcludePattern: row["md_exclude_pattern"].(string),
			Group:                row["md_group"].(string),
			CustomTags:           jsonTextToStringMap(row["md_custom_tags"].(string))}

		if md.DBType == "postgres-continuous-discovery" {
			resolved, err := ResolveDatabasesFromConfigEntry(md)
			if err != nil {
				log.Errorf("Failed to resolve DBs for \"%s\": %s", md.DBUniqueName, err)
				continue
			}
			temp_arr := make([]string, 0)
			for _, rdb := range resolved {
				monitoredDBs = append(monitoredDBs, rdb)
				temp_arr = append(temp_arr, rdb.DBName)
			}
			log.Debugf("Resolved %d DBs with prefix \"%s\": [%s]", len(resolved), md.DBUniqueName, strings.Join(temp_arr, ", "))
		} else {
			monitoredDBs = append(monitoredDBs, md)
		}

		monitoredDBs = append(monitoredDBs)
	}
	return monitoredDBs, err
}

func SendToInflux(connect_str, conn_id string, storeMessages []MetricStoreMessage) error {
	if storeMessages == nil || len(storeMessages) == 0 {
		return nil
	}
	ts_warning_printed := false
	retries := 1 // 1 retry
retry:

	c, err := client.NewHTTPClient(client.HTTPConfig{
		Addr:     connect_str,
		Username: opts.InfluxUser,
		Password: opts.InfluxPassword,
	})

	if err != nil {
		log.Error("Error connecting to Influx", conn_id, ": ", err)
		if retries > 0 {
			retries--
			time.Sleep(time.Millisecond * 200)
			goto retry
		}
		return err
	}
	defer c.Close()

	bp, err := client.NewBatchPoints(client.BatchPointsConfig{Database: opts.InfluxDbname})

	if err != nil {
		return err
	}
	rows_batched := 0
	total_rows := 0

	for _, msg := range storeMessages {
		if msg.Data == nil || len(msg.Data) == 0 {
			continue
		}
		log.Debug("SendToInflux", conn_id, "data[0] of ", len(msg.Data), ":", msg.Data[0])

		for _, dr := range msg.Data {
			// Create a point and add to batch
			var epoch_time time.Time
			var epoch_ns int64
			tags := make(map[string]string)
			fields := make(map[string]interface{})

			total_rows += 1
			tags["dbname"] = msg.DBUniqueName

			if msg.CustomTags != nil {
				for k, v := range msg.CustomTags {
					tags[k] = fmt.Sprintf("%v", v)
				}
			}

			for k, v := range dr {
				if v == nil || v == "" {
					continue // not storing NULLs
				}
				if k == EPOCH_COLUMN_NAME {
					epoch_ns = v.(int64)
				} else if strings.HasPrefix(k, "tag_") {
					tag := k[4:]
					tags[tag] = fmt.Sprintf("%v", v)
				} else {
					fields[k] = v
				}
			}

			if epoch_ns == 0 {
				if !ts_warning_printed && msg.MetricName != "pgbouncer_stats" {
					log.Warning("No timestamp_ns found, (gatherer) server time will be used. measurement:", msg.MetricName)
					ts_warning_printed = true
				}
				epoch_time = time.Now()
			} else {
				epoch_time = time.Unix(0, epoch_ns)
			}

			pt, err := client.NewPoint(msg.MetricName, tags, fields, epoch_time)

			if err != nil {
				log.Errorf("Calling NewPoint() of Influx driver failed. Datapoint \"%s\" dropped. Err: %s", dr, err)
				atomic.AddUint64(&totalMetricsDroppedCounter, 1)
				continue
			}

			bp.AddPoint(pt)
			rows_batched += 1
		}
	}
	t1 := time.Now()
	err = c.Write(bp)
	t_diff := time.Now().Sub(t1)
	if err == nil {
		if len(storeMessages) == 1 {
			log.Infof("wrote %d/%d rows to InfluxDB %s for [%s:%s] in %.1f ms", rows_batched, total_rows,
				conn_id, storeMessages[0].DBUniqueName, storeMessages[0].MetricName, float64(t_diff.Nanoseconds())/1000000.0)
		} else {
			log.Infof("wrote %d/%d rows from %d metric sets to InfluxDB %s in %.1f ms", rows_batched, total_rows,
				len(storeMessages), conn_id, float64(t_diff.Nanoseconds())/1000000.0)
		}
		lastSuccessfulDatastoreWriteTime = t1
	}
	return err
}

func InitGraphiteConnection(host string, port int) {
	var err error
	log.Debug("Connecting to Graphite...")
	graphiteConnection, err = graphite.NewGraphite(host, port)
	if err != nil {
		log.Fatal("could not connect to Graphite:", err)
	}
	log.Debug("OK")
}

func SendToGraphite(dbname, measurement string, data [](map[string]interface{})) error {
	if data == nil || len(data) == 0 {
		log.Warning("No data passed to SendToGraphite call")
		return nil
	}
	log.Debugf("Writing %d rows to Graphite", len(data))

	metric_base_prefix := GRAPHITE_METRICS_PREFIX + "." + measurement + "." + dbname + "."
	metrics := make([]graphite.Metric, 0, len(data)*len(data[0]))

	for _, dr := range data {
		var epoch_s int64

		// we loop over columns the first time just to find the timestamp
		for k, v := range dr {
			if v == nil || v == "" {
				continue // not storing NULLs
			} else if k == EPOCH_COLUMN_NAME {
				epoch_s = v.(int64) / 1e9
				break
			}
		}

		if epoch_s == 0 {
			log.Warning("No timestamp_ns found, server time will be used. measurement:", measurement)
			epoch_s = time.Now().Unix()
		}

		for k, v := range dr {
			if v == nil || v == "" {
				continue // not storing NULLs
			}
			if k == EPOCH_COLUMN_NAME {
				continue
			} else {
				var metric graphite.Metric
				if strings.HasPrefix(k, "tag_") { // ignore tags for Graphite
					metric.Name = metric_base_prefix + k[4:]
				} else {
					metric.Name = metric_base_prefix + k
				}
				switch t := v.(type) {
				case int:
					metric.Value = fmt.Sprintf("%d", v)
				case int32:
					metric.Value = fmt.Sprintf("%d", v)
				case int64:
					metric.Value = fmt.Sprintf("%d", v)
				case float64:
					metric.Value = fmt.Sprintf("%f", v)
				default:
					log.Warning("Invalid type for column:", k, "value:", v, "type:", t)
					continue
				}
				metric.Timestamp = epoch_s
				metrics = append(metrics, metric)
			}
		}
	} // dr

	log.Debug("Sending", len(metrics), "metric points to Graphite...")
	t1 := time.Now()
	err := graphiteConnection.SendMetrics(metrics)
	t2 := time.Now()
	if err != nil {
		log.Error("could not send metric to Graphite:", err)
	} else {
		lastSuccessfulDatastoreWriteTime = t1
		log.Debug("Sent in ", (t2.Sub(t1).Nanoseconds())/1000, "us")
	}

	return err
}

func GetMonitoredDatabaseByUniqueName(name string) (MonitoredDatabase, error) {
	monitored_db_cache_lock.RLock()
	defer monitored_db_cache_lock.RUnlock()
	_, exists := monitored_db_cache[name]
	if !exists {
		return MonitoredDatabase{}, errors.New("DBUnique not found")
	}
	return monitored_db_cache[name], nil
}

func UpdateMonitoredDBCache(data []MonitoredDatabase) {
	if data != nil && len(data) > 0 {
		monitored_db_cache_new := make(map[string]MonitoredDatabase)

		for _, row := range data {
			monitored_db_cache_new[row.DBUniqueName] = row
		}

		monitored_db_cache_lock.Lock()
		monitored_db_cache = monitored_db_cache_new
		monitored_db_cache_lock.Unlock()
	}
}

func ProcessRetryQueue(data_source, conn_str, conn_ident string, retry_queue *list.List, limit int) error {
	var err error
	iterations_done := 0

	for retry_queue.Len() > 0 { // send over the whole re-try queue at once if connection works
		log.Info("Processing InfluxDB retry_queue", conn_ident, ". Items in retry_queue: ", retry_queue.Len())
		msg := retry_queue.Back().Value.([]MetricStoreMessage)

		if data_source == DATASTORE_INFLUX {
			err = SendToInflux(conn_str, conn_ident, msg)
		} else if data_source == DATASTORE_GRAPHITE {
			for _, m := range msg {
				err = SendToGraphite(m.DBUniqueName, m.MetricName, m.Data) // TODO
			}
		} else {
			log.Fatal("Invalid datastore:", data_source)
		}
		if err != nil {
			if data_source == DATASTORE_INFLUX && strings.Contains(err.Error(), "unable to parse") {
				if len(msg) == 1 { // can only pinpoint faulty input data without batching
					log.Errorf("Dropping metric [%s:%s] as Influx is unable to parse the data: %v",
						msg[0].DBUniqueName, msg[0].MetricName, msg[0].Data) // ignore data points consisting of anything else than strings and floats
					atomic.AddUint64(&totalMetricsDroppedCounter, 1)
				} else {
					log.Errorf("Dropping %d metric-sets as Influx is unable to parse the data: %s", len(msg), err)
					atomic.AddUint64(&totalMetricsDroppedCounter, uint64(len(msg)))
				}
			} else {
				return err // still gone, retry later
			}
		}
		retry_queue.Remove(retry_queue.Back())
		iterations_done++
		if limit > 0 && limit == iterations_done {
			return nil
		}
	}

	return nil
}

func MetricsBatcher(data_store string, batchingMaxDelayMillis int64, buffered_storage_ch <-chan []MetricStoreMessage, storage_ch chan<- []MetricStoreMessage) {
	if batchingMaxDelayMillis <= 0 {
		log.Fatalf("Check --batching-max-delay-ms, zero/negative batching delay:", batchingMaxDelayMillis)
	}
	var datapointCounter int = 0
	var maxBatchSize int = 1000            // flush on maxBatchSize or batchingMaxDelayMillis
	batch := make([]MetricStoreMessage, 0) // no size limit here as limited in persister already
	ticker := time.NewTicker(time.Millisecond * time.Duration(batchingMaxDelayMillis))

	for {
		select {
		case <-ticker.C:
			if len(batch) > 0 {
				flushed := make([]MetricStoreMessage, len(batch))
				copy(flushed, batch)
				log.Infof("Flushing %d metric datasets due to batching timeout", len(batch))
				storage_ch <- flushed
				batch = make([]MetricStoreMessage, 0)
				datapointCounter = 0
			}
		case msg := <-buffered_storage_ch:
			for _, m := range msg { // in reality msg are sent by fetchers one by one though
				batch = append(batch, m)
				datapointCounter += len(m.Data)
				if datapointCounter > maxBatchSize { // flush. also set some last_sent_timestamp so that ticker would pass a round?
					flushed := make([]MetricStoreMessage, len(batch))
					copy(flushed, batch)
					log.Infof("Flushing %d metric datasets due to maxBatchSize limit of %d datapoints", len(batch), maxBatchSize)
					storage_ch <- flushed
					batch = make([]MetricStoreMessage, 0)
					datapointCounter = 0
				}
			}
		}
	}
}

func WriteMetricsToJsonFile(msgArr []MetricStoreMessage, jsonPath string) error {
	if len(msgArr) == 0 {
		return nil
	}

	jsonOutFile, err := os.Create(jsonPath)
	if err != nil {
		return err
	}
	defer jsonOutFile.Close()

	log.Infof("Writing %d metric sets to JSON file at \"%s\"...", len(msgArr), jsonPath)
	enc := json.NewEncoder(jsonOutFile)
	for _, msg := range msgArr {
		err = enc.Encode(map[string]interface{}{"metric": msg.MetricName, "data": msg.Data, "dbname": msg.DBUniqueName, "custom_tags": msg.CustomTags})
		if err != nil {
			return err
		}
	}
	return nil
}

func MetricsPersister(data_store string, storage_ch <-chan []MetricStoreMessage) {
	var last_try = make([]time.Time, influx_host_count)          // if Influx errors out, don't retry before 10s
	var last_drop_warning = make([]time.Time, influx_host_count) // log metric points drops every 10s to not overflow logs in case Influx is down for longer
	var retry_queues = make([]*list.List, influx_host_count)     // separate queues for all Influx hosts
	var in_error = make([]bool, influx_host_count)
	var err error

	for i := 0; i < influx_host_count; i++ {
		retry_queues[i] = list.New()
	}

	for {
		select {
		case msg_arr := <-storage_ch:

			for i, retry_queue := range retry_queues {

				retry_queue_length := retry_queue.Len()

				if retry_queue_length > 0 {
					if retry_queue_length == PERSIST_QUEUE_MAX_SIZE {
						dropped_msgs := retry_queue.Remove(retry_queue.Back())
						datasets_dropped := len(dropped_msgs.([]MetricStoreMessage))
						datapoints_dropped := 0
						for _, msg := range dropped_msgs.([]MetricStoreMessage) {
							datapoints_dropped += len(msg.Data)
						}
						atomic.AddUint64(&totalMetricsDroppedCounter, uint64(datapoints_dropped))
						if last_drop_warning[i].IsZero() || last_drop_warning[i].Before(time.Now().Add(time.Second*-10)) {
							log.Warningf("Dropped %d oldest data sets with %d data points from queue %d as PERSIST_QUEUE_MAX_SIZE = %d exceeded",
								datasets_dropped, datapoints_dropped, i, PERSIST_QUEUE_MAX_SIZE)
							last_drop_warning[i] = time.Now()
						}
					}
					retry_queue.PushFront(msg_arr)
				} else {
					if data_store == DATASTORE_INFLUX {
						err = SendToInflux(InfluxConnectStrings[i], strconv.Itoa(i), msg_arr)
					} else if data_store == DATASTORE_GRAPHITE {
						for _, m := range msg_arr {
							err = SendToGraphite(m.DBUniqueName, m.MetricName, m.Data) // TODO does Graphite library support batching?
						}
					} else if data_store == DATASTORE_JSON {
						err = WriteMetricsToJsonFile(msg_arr, opts.JsonStorageFile)
					} else {
						log.Fatal("Invalid datastore:", data_store)
					}
					last_try[i] = time.Now()
					if err != nil {
						if strings.Contains(err.Error(), "unable to parse") {
							if len(msg_arr) == 1 {
								log.Errorf("Dropping metric [%s:%s] as Influx is unable to parse the data: %s",
									msg_arr[0].DBUniqueName, msg_arr[0].MetricName, msg_arr[0].Data) // ignore data points consisting of anything else than strings and floats
							} else {
								log.Errorf("Dropping %d metric-sets as Influx is unable to parse the data: %s", len(msg_arr), err)
								// TODO loop over single metrics in case of errors?
							}
						} else {
							log.Errorf("Failed to write into datastore %d: %s", i, err)
							in_error[i] = true
							retry_queue.PushFront(msg_arr)
						}
					}
				}
			}
		default:
			for i, retry_queue := range retry_queues {
				if retry_queue.Len() > 0 && (!in_error[i] || last_try[i].Before(time.Now().Add(time.Second*-10))) {
					err := ProcessRetryQueue(data_store, InfluxConnectStrings[i], strconv.Itoa(i), retry_queue, 100)
					if err != nil {
						log.Error("Error processing retry queue", i, ":", err)
						in_error[i] = true
					} else {
						in_error[i] = false
					}
					last_try[i] = time.Now()
				} else {
					time.Sleep(time.Millisecond * 100) // nothing in queue nor in channel
				}
			}
		}
	}
}

func DBGetPGVersion(dbUnique string) (DBVersionMapEntry, error) {
	var ver DBVersionMapEntry
	var ok bool
	sql := `
		select (regexp_matches(
			regexp_replace(current_setting('server_version'), '(beta|devel).*', '', 'g'),
			E'\\d+\\.?\\d+?')
			)[1]::text as ver, pg_is_in_recovery();
	`

	db_pg_version_map_lock.RLock()
	ver, ok = db_pg_version_map[dbUnique]
	db_pg_version_map_lock.RUnlock()

	if ok && ver.LastCheckedOn.After(time.Now().Add(time.Minute*-2)) { // use cached version for 2 min
		log.Debugf("using cached postgres version %s for %s", ver.Version.String(), dbUnique)
		return ver, nil
	} else {
		log.Debug("determining DB version for", dbUnique)
		data, err, _ := DBExecReadByDbUniqueName(dbUnique, "", useConnPooling, sql)
		if err != nil {
			log.Error("DBGetPGVersion failed", err)
			return ver, err
		}
		ver.Version, _ = decimal.NewFromString(data[0]["ver"].(string))
		ver.IsInRecovery = data[0]["pg_is_in_recovery"].(bool)
		ver.LastCheckedOn = time.Now()

		db_pg_version_map_lock.Lock()
		db_pg_version_map[dbUnique] = ver
		db_pg_version_map_lock.Unlock()
	}
	return ver, nil
}

// Need to define a sort interface as Go doesn't have support for Numeric/Decimal
type Decimal []decimal.Decimal

func (a Decimal) Len() int           { return len(a) }
func (a Decimal) Swap(i, j int)      { a[i], a[j] = a[j], a[i] }
func (a Decimal) Less(i, j int) bool { return a[i].LessThan(a[j]) }

// assumes upwards compatibility for versions
func GetSQLForMetricPGVersion(metric string, pgVer decimal.Decimal, metricDefMap map[string]map[decimal.Decimal]string) (string, error) {
	var keys []decimal.Decimal
	var mdm map[string]map[decimal.Decimal]string

	if metricDefMap != nil {
		mdm = metricDefMap
	} else {
		mdm = metric_def_map // global cache
	}

	metric_def_map_lock.RLock()

	defer metric_def_map_lock.RUnlock()

	_, ok := mdm[metric]
	if !ok || len(mdm[metric]) == 0 {
		log.Error("metric", metric, "not found")
		return "", errors.New("metric SQL not found")
	}

	for k := range mdm[metric] {
		keys = append(keys, k)
	}

	sort.Sort(Decimal(keys))

	var best_ver decimal.Decimal
	var found bool
	for _, ver := range keys {
		if pgVer.GreaterThanOrEqual(ver) {
			best_ver = ver
			found = true
		}
	}

	if !found {
		return "", errors.New(fmt.Sprintf("suitable SQL not found for metric \"%s\", version \"%s\"", metric, pgVer))
	}

	return mdm[metric][best_ver], nil
}

func DetectSprocChanges(dbUnique string, db_pg_version decimal.Decimal, storage_ch chan<- []MetricStoreMessage, host_state map[string]map[string]string) ChangeDetectionResults {
	detected_changes := make([](map[string]interface{}), 0)
	var first_run bool
	var change_counts ChangeDetectionResults

	log.Debug("checking for sproc changes...")
	if _, ok := host_state["sproc_hashes"]; !ok {
		first_run = true
		host_state["sproc_hashes"] = make(map[string]string)
	}

	sql, err := GetSQLForMetricPGVersion("sproc_hashes", db_pg_version, nil)
	if err != nil {
		log.Error("could not get sproc_hashes sql:", err)
		return change_counts
	}

	data, err, _ := DBExecReadByDbUniqueName(dbUnique, "sproc_hashes", useConnPooling, sql)
	if err != nil {
		log.Error("could not read table_hashes from monitored host: ", dbUnique, ", err:", err)
		return change_counts
	}

	for _, dr := range data {
		obj_ident := dr["tag_sproc"].(string) + ":" + dr["tag_oid"].(string)
		prev_hash, ok := host_state["sproc_hashes"][obj_ident]
		if ok { // we have existing state
			if prev_hash != dr["md5"].(string) {
				log.Warning("detected change in sproc:", dr["tag_sproc"], ", oid:", dr["tag_oid"])
				dr["event"] = "alter"
				detected_changes = append(detected_changes, dr)
				host_state["sproc_hashes"][obj_ident] = dr["md5"].(string)
				change_counts.Altered += 1
			}
		} else { // check for new / delete
			if !first_run {
				log.Warning("detected new sproc:", dr["tag_sproc"], ", oid:", dr["tag_oid"])
				dr["event"] = "create"
				detected_changes = append(detected_changes, dr)
				change_counts.Created += 1
			}
			host_state["sproc_hashes"][obj_ident] = dr["md5"].(string)
		}
	}
	// detect deletes
	if !first_run && len(host_state["sproc_hashes"]) != len(data) {
		deleted_sprocs := make([]string, 0)
		// turn resultset to map => [oid]=true for faster checks
		current_oid_map := make(map[string]bool)
		for _, dr := range data {
			current_oid_map[dr["tag_sproc"].(string)+":"+dr["tag_oid"].(string)] = true
		}
		for sproc_ident, _ := range host_state["sproc_hashes"] {
			_, ok := current_oid_map[sproc_ident]
			if !ok {
				splits := strings.Split(sproc_ident, ":")
				log.Warning("detected delete of sproc:", splits[0], ", oid:", splits[1])
				influx_entry := make(map[string]interface{})
				influx_entry["event"] = "drop"
				influx_entry["tag_sproc"] = splits[0]
				influx_entry["tag_oid"] = splits[1]
				if len(data) > 0 {
					influx_entry["epoch_ns"] = data[0]["epoch_ns"]
				} else {
					influx_entry["epoch_ns"] = time.Now().UnixNano()
				}
				detected_changes = append(detected_changes, influx_entry)
				deleted_sprocs = append(deleted_sprocs, sproc_ident)
				change_counts.Dropped += 1
			}
		}
		for _, deleted_sproc := range deleted_sprocs {
			delete(host_state["sproc_hashes"], deleted_sproc)
		}
	}
	if len(detected_changes) > 0 {
		md, _ := GetMonitoredDatabaseByUniqueName(dbUnique)
		storage_ch <- []MetricStoreMessage{MetricStoreMessage{DBUniqueName: dbUnique, MetricName: "sproc_changes", Data: detected_changes, CustomTags: md.CustomTags}}
	}

	return change_counts
}

func DetectTableChanges(dbUnique string, db_pg_version decimal.Decimal, storage_ch chan<- []MetricStoreMessage, host_state map[string]map[string]string) ChangeDetectionResults {
	detected_changes := make([](map[string]interface{}), 0)
	var first_run bool
	var change_counts ChangeDetectionResults

	log.Debug("checking for table changes...")
	if _, ok := host_state["table_hashes"]; !ok {
		first_run = true
		host_state["table_hashes"] = make(map[string]string)
	}

	sql, err := GetSQLForMetricPGVersion("table_hashes", db_pg_version, nil)
	if err != nil {
		log.Error("could not get table_hashes sql:", err)
		return change_counts
	}

	data, err, _ := DBExecReadByDbUniqueName(dbUnique, "table_hashes", useConnPooling, sql)
	if err != nil {
		log.Error("could not read table_hashes from monitored host:", dbUnique, ", err:", err)
		return change_counts
	}

	for _, dr := range data {
		obj_ident := dr["tag_table"].(string)
		prev_hash, ok := host_state["table_hashes"][obj_ident]
		log.Debug("inspecting table:", obj_ident, "hash:", prev_hash)
		if ok { // we have existing state
			if prev_hash != dr["md5"].(string) {
				log.Warning("detected DDL change in table:", dr["tag_table"])
				dr["event"] = "alter"
				detected_changes = append(detected_changes, dr)
				host_state["table_hashes"][obj_ident] = dr["md5"].(string)
				change_counts.Altered += 1
			}
		} else { // check for new / delete
			if !first_run {
				log.Warning("detected new table:", dr["tag_table"])
				dr["event"] = "create"
				detected_changes = append(detected_changes, dr)
				change_counts.Created += 1
			}
			host_state["table_hashes"][obj_ident] = dr["md5"].(string)
		}
	}
	// detect deletes
	if !first_run && len(host_state["table_hashes"]) != len(data) {
		deleted_tables := make([]string, 0)
		// turn resultset to map => [table]=true for faster checks
		current_table_map := make(map[string]bool)
		for _, dr := range data {
			current_table_map[dr["tag_table"].(string)] = true
		}
		for table, _ := range host_state["table_hashes"] {
			_, ok := current_table_map[table]
			if !ok {
				log.Warning("detected drop of table:", table)
				influx_entry := make(map[string]interface{})
				influx_entry["event"] = "drop"
				influx_entry["tag_table"] = table
				if len(data) > 0 {
					influx_entry["epoch_ns"] = data[0]["epoch_ns"]
				} else {
					influx_entry["epoch_ns"] = time.Now().UnixNano()
				}
				detected_changes = append(detected_changes, influx_entry)
				deleted_tables = append(deleted_tables, table)
				change_counts.Dropped += 1
			}
		}
		for _, deleted_table := range deleted_tables {
			delete(host_state["table_hashes"], deleted_table)
		}
	}

	if len(detected_changes) > 0 {
		md, _ := GetMonitoredDatabaseByUniqueName(dbUnique)
		storage_ch <- []MetricStoreMessage{MetricStoreMessage{DBUniqueName: dbUnique, MetricName: "table_changes", Data: detected_changes, CustomTags: md.CustomTags}}
	}

	return change_counts
}

func DetectIndexChanges(dbUnique string, db_pg_version decimal.Decimal, storage_ch chan<- []MetricStoreMessage, host_state map[string]map[string]string) ChangeDetectionResults {
	detected_changes := make([](map[string]interface{}), 0)
	var first_run bool
	var change_counts ChangeDetectionResults

	log.Debug("checking for index changes...")
	if _, ok := host_state["index_hashes"]; !ok {
		first_run = true
		host_state["index_hashes"] = make(map[string]string)
	}

	sql, err := GetSQLForMetricPGVersion("index_hashes", db_pg_version, nil)
	if err != nil {
		log.Error("could not get index_hashes sql:", err)
		return change_counts
	}

	data, err, _ := DBExecReadByDbUniqueName(dbUnique, "index_hashes", useConnPooling, sql)
	if err != nil {
		log.Error("could not read index_hashes from monitored host:", dbUnique, ", err:", err)
		return change_counts
	}

	for _, dr := range data {
		obj_ident := dr["tag_index"].(string)
		prev_hash, ok := host_state["index_hashes"][obj_ident]
		if ok { // we have existing state
			if prev_hash != (dr["md5"].(string) + dr["is_valid"].(string)) {
				log.Warning("detected index change:", dr["tag_index"], ", table:", dr["table"])
				dr["event"] = "alter"
				detected_changes = append(detected_changes, dr)
				host_state["index_hashes"][obj_ident] = dr["md5"].(string) + dr["is_valid"].(string)
				change_counts.Altered += 1
			}
		} else { // check for new / delete
			if !first_run {
				log.Warning("detected new index:", dr["tag_index"])
				dr["event"] = "create"
				detected_changes = append(detected_changes, dr)
				change_counts.Created += 1
			}
			host_state["index_hashes"][obj_ident] = dr["md5"].(string) + dr["is_valid"].(string)
		}
	}
	// detect deletes
	if !first_run && len(host_state["index_hashes"]) != len(data) {
		deleted_indexes := make([]string, 0)
		// turn resultset to map => [table]=true for faster checks
		current_index_map := make(map[string]bool)
		for _, dr := range data {
			current_index_map[dr["tag_index"].(string)] = true
		}
		for index_name, _ := range host_state["index_hashes"] {
			_, ok := current_index_map[index_name]
			if !ok {
				log.Warning("detected drop of index_name:", index_name)
				influx_entry := make(map[string]interface{})
				influx_entry["event"] = "drop"
				influx_entry["tag_index"] = index_name
				if len(data) > 0 {
					influx_entry["epoch_ns"] = data[0]["epoch_ns"]
				} else {
					influx_entry["epoch_ns"] = time.Now().UnixNano()
				}
				detected_changes = append(detected_changes, influx_entry)
				deleted_indexes = append(deleted_indexes, index_name)
				change_counts.Dropped += 1
			}
		}
		for _, deleted_index := range deleted_indexes {
			delete(host_state["index_hashes"], deleted_index)
		}
	}
	if len(detected_changes) > 0 {
		md, _ := GetMonitoredDatabaseByUniqueName(dbUnique)
		storage_ch <- []MetricStoreMessage{MetricStoreMessage{DBUniqueName: dbUnique, MetricName: "index_changes", Data: detected_changes, CustomTags: md.CustomTags}}
	}

	return change_counts
}

func DetectConfigurationChanges(dbUnique string, db_pg_version decimal.Decimal, storage_ch chan<- []MetricStoreMessage, host_state map[string]map[string]string) ChangeDetectionResults {
	detected_changes := make([](map[string]interface{}), 0)
	var first_run bool
	var change_counts ChangeDetectionResults

	log.Debug("checking for pg_settings changes...")
	if _, ok := host_state["configuration_hashes"]; !ok {
		first_run = true
		host_state["configuration_hashes"] = make(map[string]string)
	}

	sql, err := GetSQLForMetricPGVersion("configuration_hashes", db_pg_version, nil)
	if err != nil {
		log.Error("could not get index_hashes sql:", err)
		return change_counts
	}

	data, err, _ := DBExecReadByDbUniqueName(dbUnique, "configuration_hashes", useConnPooling, sql)
	if err != nil {
		log.Error("could not read configuration_hashes from monitored host:", dbUnique, ", err:", err)
		return change_counts
	}

	for _, dr := range data {
		obj_ident := dr["tag_setting"].(string)
		prev_hash, ok := host_state["configuration_hashes"][obj_ident]
		if ok { // we have existing state
			if prev_hash != dr["value"].(string) {
				log.Warningf("detected settings change: %s = %s (prev: %s)",
					dr["tag_setting"], dr["value"], prev_hash)
				dr["event"] = "alter"
				detected_changes = append(detected_changes, dr)
				host_state["configuration_hashes"][obj_ident] = dr["value"].(string)
				change_counts.Altered += 1
			}
		} else { // check for new, delete not relevant here (pg_upgrade)
			if !first_run {
				log.Warning("detected new setting:", dr["tag_setting"])
				dr["event"] = "create"
				detected_changes = append(detected_changes, dr)
				change_counts.Created += 1
			}
			host_state["configuration_hashes"][obj_ident] = dr["value"].(string)
		}
	}

	if len(detected_changes) > 0 {
		md, _ := GetMonitoredDatabaseByUniqueName(dbUnique)
		storage_ch <- []MetricStoreMessage{MetricStoreMessage{DBUniqueName: dbUnique, MetricName: "configuration_changes", Data: detected_changes, CustomTags: md.CustomTags}}
	}

	return change_counts
}

func CheckForPGObjectChangesAndStore(dbUnique string, db_pg_version decimal.Decimal, storage_ch chan<- []MetricStoreMessage, host_state map[string]map[string]string) {
	sproc_counts := DetectSprocChanges(dbUnique, db_pg_version, storage_ch, host_state) // TODO some of Detect*() code could be unified...
	table_counts := DetectTableChanges(dbUnique, db_pg_version, storage_ch, host_state)
	index_counts := DetectIndexChanges(dbUnique, db_pg_version, storage_ch, host_state)
	conf_counts := DetectConfigurationChanges(dbUnique, db_pg_version, storage_ch, host_state)

	// need to send info on all object changes as one message as Grafana applies "last wins" for annotations with similar timestamp
	message := ""
	if sproc_counts.Altered > 0 || sproc_counts.Created > 0 || sproc_counts.Dropped > 0 {
		message += fmt.Sprintf(" sprocs %d/%d/%d", sproc_counts.Created, sproc_counts.Altered, sproc_counts.Dropped)
	}
	if table_counts.Altered > 0 || table_counts.Created > 0 || table_counts.Dropped > 0 {
		message += fmt.Sprintf(" tables/views %d/%d/%d", table_counts.Created, table_counts.Altered, table_counts.Dropped)
	}
	if index_counts.Altered > 0 || index_counts.Created > 0 || index_counts.Dropped > 0 {
		message += fmt.Sprintf(" indexes %d/%d/%d", index_counts.Created, index_counts.Altered, index_counts.Dropped)
	}
	if conf_counts.Altered > 0 || conf_counts.Created > 0 {
		message += fmt.Sprintf(" configuration %d/%d/%d", conf_counts.Created, conf_counts.Altered, conf_counts.Dropped)
	}
	if message > "" {
		message = "Detected changes for \"" + dbUnique + "\" [Created/Altered/Dropped]:" + message
		log.Warning("message", message)
		detected_changes_summary := make([](map[string]interface{}), 0)
		influx_entry := make(map[string]interface{})
		influx_entry["details"] = message
		influx_entry["epoch_ns"] = time.Now().UnixNano()
		detected_changes_summary = append(detected_changes_summary, influx_entry)
		md, _ := GetMonitoredDatabaseByUniqueName(dbUnique)
		storage_ch <- []MetricStoreMessage{MetricStoreMessage{DBUniqueName: dbUnique, DBType: "postgres", MetricName: "object_changes", Data: detected_changes_summary, CustomTags: md.CustomTags}}
	}
}

func FilterPgbouncerData(data []map[string]interface{}, database_to_keep string) []map[string]interface{} {
	filtered_data := make([]map[string]interface{}, 0)

	if len(database_to_keep) > 0 {
		for _, dr := range data {
			log.Debug("dr", dr)
			_, ok := dr["database"]
			if !ok {
				log.Warning("Expected 'database' key not found from pgbouncer_stats, not storing data")
				continue
			}
			if dr["database"] != database_to_keep {
				continue // we only want pgbouncer stats for the DB specified in monitored_dbs.md_dbname
			}
			delete(dr, "database") // remove 'database' as we use 'dbname' by convention
			filtered_data = append(filtered_data, dr)
		}
	}
	return filtered_data
}

func FetchAndStore(msg MetricFetchMessage, host_state map[string]map[string]string, storage_ch chan<- []MetricStoreMessage) (int, error) {
	var db_pg_version decimal.Decimal
	var err error

	if msg.DBType == "postgres" {
		ver, err := DBGetPGVersion(msg.DBUniqueName)
		if err != nil {
			log.Error("failed to fetch pg version for ", msg.DBUniqueName, msg.MetricName, err)
			return 0, err
		}
		db_pg_version = ver.Version
	} else if msg.DBType == "pgbouncer" {
		db_pg_version = decimal.Decimal{} // version is 0.0 for all pgbouncer sql per convention
		// as surprisingly pgbouncer 'show version' outputs it as 'NOTICE'
		// which cannot be accessed from Go lib/pg
	}

	sql, err := GetSQLForMetricPGVersion(msg.MetricName, db_pg_version, nil)
	if err != nil {
		epoch, ok := last_sql_fetch_error.Load(msg.MetricName + ":" + db_pg_version.String())
		if !ok || ((time.Now().Unix() - epoch.(int64)) > 3600) { // complain only 1x per hour
			log.Warningf("Failed to get SQL for metric '%s', version '%s'", msg.MetricName, db_pg_version)
			last_sql_fetch_error.Store(msg.MetricName+":"+db_pg_version.String(), time.Now().Unix())
		}
		return 0, err
	}

	if msg.MetricName == "change_events" { // special handling, multiple queries + stateful
		CheckForPGObjectChangesAndStore(msg.DBUniqueName, db_pg_version, storage_ch, host_state)
	} else {

		data, err, duration := DBExecReadByDbUniqueName(msg.DBUniqueName, msg.MetricName, useConnPooling, sql)

		if err != nil {
			if strings.Contains(err.Error(), "empty SQL") { // empty / dummy SQL is used for metrics that became available at a certain version
				log.Infof("Ignoring fetch message - got an empty/dummy SQL string for [%s:%s]", msg.DBUniqueName, msg.MetricName)
				return 0, err
			}
			// let's soften errors to "info" from functions that expect the server to be a primary to reduce noise
			if strings.Contains(err.Error(), "recovery is in progress") {
				db_pg_version_map_lock.RLock()
				ver, _ := db_pg_version_map[msg.DBUniqueName]
				db_pg_version_map_lock.RUnlock()
				if ver.IsInRecovery {
					log.Infof("failed to fetch metrics for '%s', metric '%s': %s", msg.DBUniqueName, msg.MetricName, err)
					return 0, err
				}
			}
			log.Errorf("failed to fetch metrics for '%s', metric '%s': %s", msg.DBUniqueName, msg.MetricName, err)
		} else {
			md, err := GetMonitoredDatabaseByUniqueName(msg.DBUniqueName)
			if err != nil {
				log.Errorf("could not get monitored DB details for %s: %s", msg.DBUniqueName, err)
				return len(data), err
			}

			log.Infof("fetched %d rows for [%s:%s] in %.1f ms", len(data), msg.DBUniqueName, msg.MetricName, float64(duration.Nanoseconds())/1000000)
			if msg.MetricName == "pgbouncer_stats" { // clean unwanted pgbouncer pool stats here as not possible in SQL
				data = FilterPgbouncerData(data, md.DBName)
			}
			if len(data) > 0 {
				atomic.AddUint64(&totalMetricsFetchedCounter, uint64(len(data)))
				atomic.AddUint64(&totalDatasetsFetchedCounter, 1)
				storage_ch <- []MetricStoreMessage{MetricStoreMessage{DBUniqueName: msg.DBUniqueName, MetricName: msg.MetricName, Data: data, CustomTags: md.CustomTags}}
				return len(data), nil
			}
		}
	}
	return 0, nil
}

// ControlMessage notifies of shutdown + interval change
func MetricGathererLoop(dbUniqueName, dbType, metricName string, config_map map[string]float64, control_ch <-chan ControlMessage, store_ch chan<- []MetricStoreMessage) {
	config := config_map
	interval := config[metricName]
	ticker := time.NewTicker(time.Millisecond * time.Duration(interval*1000))
	host_state := make(map[string]map[string]string)
	last_error_notification_time := time.Now()
	failed_fetches := 0

	for {

		t1 := time.Now()
		_, err := FetchAndStore(
			MetricFetchMessage{DBUniqueName: dbUniqueName, MetricName: metricName, DBType: dbType},
			host_state,
			store_ch)
		t2 := time.Now()
		if err != nil {
			if last_error_notification_time.Add(time.Second * time.Duration(600)).Before(time.Now()) {
				log.Errorf("Total failed fetches for [%s:%s]: %d", failed_fetches)
				last_error_notification_time = time.Now()
			}
			failed_fetches += 1
		}

		if t2.Sub(t1) > (time.Second * time.Duration(interval)) {
			log.Warningf("Total fetching time of %v bigger than %vs interval for [%s:%s]", t2.Sub(t1), interval, dbUniqueName, metricName)
		}

		select {
		case msg := <-control_ch:
			log.Debug("got control msg", dbUniqueName, metricName, msg)
			if msg.Action == GATHERER_STATUS_START {
				config = msg.Config
				interval = config[metricName]
				if ticker != nil {
					ticker.Stop()
				}
				ticker = time.NewTicker(time.Millisecond * time.Duration(interval*1000))
				log.Debug("started MetricGathererLoop for ", dbUniqueName, metricName, " interval:", interval)
			} else if msg.Action == GATHERER_STATUS_STOP {
				log.Debug("exiting MetricGathererLoop for ", dbUniqueName, metricName, " interval:", interval)
				return
			}
		case <-ticker.C:
			log.Debugf("MetricGathererLoop for [%s:%s] slept for %s", dbUniqueName, metricName, time.Second*time.Duration(interval))
		}

	}
}

func UpdateMetricDefinitionMap(newMetrics map[string]map[decimal.Decimal]string) {
	metric_def_map_lock.Lock()
	metric_def_map = newMetrics
	metric_def_map_lock.Unlock()
	//log.Debug("metric_def_map:", metric_def_map)
	log.Info("metrics definitions refreshed - nr. found:", len(newMetrics))
}

func ReadMetricDefinitionMapFromPostgres(failOnError bool) (map[string]map[decimal.Decimal]string, error) {
	metric_def_map_new := make(map[string]map[decimal.Decimal]string)
	sql := "select m_name, m_pg_version_from::text, m_sql from pgwatch2.metric where m_is_active"

	log.Info("updating metrics definitons from ConfigDB...")
	data, err := DBExecRead(configDb, "configDb", sql)
	if err != nil {
		if failOnError {
			log.Fatal(err)
		} else {
			log.Error(err)
			return metric_def_map, err
		}
	}
	if len(data) == 0 {
		log.Warning("no metric definitions found from config DB")
		return metric_def_map_new, err
	}

	log.Debug(len(data), "active metrics found from config db (pgwatch2.metric)")
	for _, row := range data {
		_, ok := metric_def_map_new[row["m_name"].(string)]
		if !ok {
			metric_def_map_new[row["m_name"].(string)] = make(map[decimal.Decimal]string)
		}
		d, _ := decimal.NewFromString(row["m_pg_version_from"].(string))
		metric_def_map_new[row["m_name"].(string)][d] = row["m_sql"].(string)
	}
	return metric_def_map_new, err
}

func jsonTextToMap(jsonText string) map[string]float64 {

	var host_config map[string]interface{}
	if err := json.Unmarshal([]byte(jsonText), &host_config); err != nil {
		panic(err)
	}
	retmap := make(map[string]float64)
	for k, v := range host_config {
		retmap[k] = v.(float64)
	}
	return retmap
}

func jsonTextToStringMap(jsonText string) map[string]string {

	var iMap map[string]interface{}
	if err := json.Unmarshal([]byte(jsonText), &iMap); err != nil {
		panic(err)
	}
	retmap := make(map[string]string)
	for k, v := range iMap {
		retmap[k] = fmt.Sprintf("%v", v)
	}
	return retmap
}

// queryDB convenience function to query the database
func queryDB(clnt client.Client, cmd string) (res []client.Result, err error) {
	q := client.Query{
		Command:  cmd,
		Database: opts.InfluxDbname,
	}
	if response, err := clnt.Query(q); err == nil {
		if response.Error() != nil {
			return res, response.Error()
		}
		res = response.Results
	} else {
		return res, err
	}
	return res, nil
}

func InitAndTestInfluxConnection(HostId, InfluxHost, InfluxPort, InfluxDbname, InfluxUser, InfluxPassword, InfluxSSL, SkipSSLCertVerify string, RetentionPeriod int64) (string, error) {
	log.Infof("Testing Influx connection to host %s: %s, port: %s, DB: %s", HostId, InfluxHost, InfluxPort, InfluxDbname)
	var connect_string string
	skipSSLCertVerify, _ := strconv.ParseBool(SkipSSLCertVerify)

	if b, _ := strconv.ParseBool(InfluxSSL); b == true {
		connect_string = fmt.Sprintf("https://%s:%s", InfluxHost, InfluxPort)
	} else {
		connect_string = fmt.Sprintf("http://%s:%s", InfluxHost, InfluxPort)
	}

	// Make client
	c, err := client.NewHTTPClient(client.HTTPConfig{
		Addr:               connect_string,
		Username:           InfluxUser,
		Password:           InfluxPassword,
		InsecureSkipVerify: skipSSLCertVerify,
	})

	if err != nil {
		log.Fatal("Getting Influx client failed", err)
	}

	res, err := queryDB(c, "SHOW DATABASES")
	retries := 3
retry:
	if err != nil {
		if retries > 0 {
			log.Error("SHOW DATABASES failed, retrying in 5s (max 3x)...", err)
			time.Sleep(time.Second * 5)
			retries = retries - 1
			goto retry
		} else {
			return connect_string, err
		}
	}

	for _, db_arr := range res[0].Series[0].Values {
		log.Debug("Found db:", db_arr[0])
		if InfluxDbname == db_arr[0] {
			log.Info(fmt.Sprintf("Database '%s' existing", InfluxDbname))
			return connect_string, nil
		}
	}

	log.Warningf("Database '%s' not found! Creating with %d retention and retention policy name \"%s\"...", InfluxDbname, RetentionPeriod, opts.InfluxRetentionName)
	isql := fmt.Sprintf("CREATE DATABASE %s WITH DURATION %dd REPLICATION 1 SHARD DURATION 1d NAME %s", InfluxDbname, RetentionPeriod, opts.InfluxRetentionName)
	res, err = queryDB(c, isql)
	if err != nil {
		log.Fatal(err)
	} else {
		log.Infof("Database 'pgwatch2' created on InfluxDB host %s:%s", InfluxHost, InfluxPort)
	}

	return connect_string, nil
}

func DoesFunctionExists(dbUnique, functionName string) bool {
	log.Debug("Checking for function existance", dbUnique, functionName)
	sql := fmt.Sprintf("select 1 from pg_proc join pg_namespace n on pronamespace = n.oid where proname = '%s' and n.nspname = 'public'", functionName)
	data, err, _ := DBExecReadByDbUniqueName(dbUnique, "", useConnPooling, sql)
	if err != nil {
		log.Error("Failed to check for function existance", dbUnique, functionName, err)
		return false
	}
	if len(data) > 0 {
		log.Debugf("Function %s exists on %s", functionName, dbUnique)
		return true
	}
	return false
}

// Called once on daemon startup to try to create "metric fething helper" functions automatically
func TryCreateMetricsFetchingHelpers(dbUnique string) error {
	db_pg_version, err := DBGetPGVersion(dbUnique)
	if err != nil {
		log.Errorf("Failed to fetch pg version for \"%s\": %s", dbUnique, err)
		return err
	}

	if fileBased {
		helpers, err := ReadMetricsFromFolder(path.Join(opts.MetricsFolder, FILE_BASED_METRIC_HELPERS_DIR), false)
		if err != nil {
			log.Errorf("Failed to fetch helpers from \"%s\": %s", path.Join(opts.MetricsFolder, FILE_BASED_METRIC_HELPERS_DIR), err)
			return err
		}
		log.Debug("%d helper definitions found from \"%s\"...", len(helpers), path.Join(opts.MetricsFolder, FILE_BASED_METRIC_HELPERS_DIR))

		for helperName, _ := range helpers {
			if !DoesFunctionExists(dbUnique, helperName) {

				log.Debug("Trying to create metric fetching helpers for", dbUnique, helperName)
				sql, err := GetSQLForMetricPGVersion(helperName, db_pg_version.Version, helpers)
				if err != nil {
					log.Warning("Could not find query text for", dbUnique, helperName)
					continue
				}
				_, err, _ = DBExecReadByDbUniqueName(dbUnique, "", useConnPooling, sql)
				if err != nil {
					log.Warning("Failed to create a metric fetching helper for", dbUnique, helperName)
					log.Warning(err)
				} else {
					log.Warning("Successfully created metric fetching helper for", dbUnique, helperName)
				}
			}
		}

	} else {
		sql_helpers := "select distinct m_name from pgwatch2.metric where m_is_active and m_is_helper" // m_name is a helper function name
		data, err := DBExecRead(configDb, "configDb", sql_helpers)
		if err != nil {
			log.Error(err)
			return err
		}
		for _, row := range data {
			metric := row["m_name"].(string)

			if !DoesFunctionExists(dbUnique, metric) {

				log.Debug("Trying to create metric fetching helpers for", dbUnique, metric)
				sql, err := GetSQLForMetricPGVersion(metric, db_pg_version.Version, nil)
				if err != nil {
					log.Warning("Could not find query text for", dbUnique, metric)
					continue
				}
				_, err, _ = DBExecReadByDbUniqueName(dbUnique, "", true, sql)
				if err != nil {
					log.Warning("Failed to create a metric fetching helper for", dbUnique, metric)
					log.Warning(err)
				} else {
					log.Warning("Successfully created metric fetching helper for", dbUnique, metric)
				}
			}
		}
	}
	return nil
}

// Expects "preset metrics" definition file named preset-config.yaml to be present in provided --metrics folder
func ReadPresetMetricsConfigFromFolder(folder string, failOnError bool) (map[string]map[string]float64, error) {
	pmm := make(map[string]map[string]float64)

	log.Infof("Reading preset metric config from path %s ...", folder)
	preset_metrics, err := ioutil.ReadFile(path.Join(folder, PRESET_CONFIG_YAML_FILE))
	if err != nil {
		log.Errorf("Failed to read preset metric config definition at: %s", folder)
		return pmm, err
	}
	pcs := make([]PresetConfig, 0)
	err = yaml.Unmarshal(preset_metrics, &pcs)
	if err != nil {
		log.Errorf("Unmarshaling error reading preset metric config: %v", err)
		return pmm, err
	}
	for _, pc := range pcs {
		pmm[pc.Name] = pc.Metrics
	}
	log.Infof("%d preset metric definitions found", len(pcs))
	return pmm, err
}

// expected is following structure: metric_name/pg_ver/metric.sql
func ReadMetricsFromFolder(folder string, failOnError bool) (map[string]map[decimal.Decimal]string, error) {
	metrics_map := make(map[string]map[decimal.Decimal]string)
	rIsDigitOrPunctuation := regexp.MustCompile("^[\\d\\.]+$")

	log.Infof("Searching for metrics from path %s ...", folder)
	metric_folders, err := ioutil.ReadDir(folder)
	if err != nil {
		if failOnError {
			log.Fatalf("Could not read path %s: %s", folder, err)
		}
		log.Error(err)
		return metrics_map, err
	}

	for _, f := range metric_folders {
		if f.IsDir() {
			if f.Name() == FILE_BASED_METRIC_HELPERS_DIR {
				continue // helpers are pulled in when needed
			}
			log.Debugf("Processing metric: %s", f.Name())
			pgVers, err := ioutil.ReadDir(path.Join(folder, f.Name()))
			if err != nil {
				log.Error(err)
				return metrics_map, err
			}

			for _, pgVer := range pgVers {
				if strings.HasSuffix(pgVer.Name(), ".md") {
					continue
				}
				if !rIsDigitOrPunctuation.MatchString(pgVer.Name()) {
					log.Warningf("Invalid metric stucture - version folder names should consist of only numerics/dots, found: %s", pgVer.Name())
					continue
				}
				d, err := decimal.NewFromString(pgVer.Name())
				if err != nil {
					log.Errorf("Could not parse \"%s\" to Decimal: %s", pgVer.Name(), err)
					continue
				}
				log.Debugf("Found %s", pgVer.Name())
				p := path.Join(folder, f.Name(), pgVer.Name(), "metric.sql")
				metric_sql, err := ioutil.ReadFile(p)
				if err != nil {
					log.Errorf("Failed to read metric definition at: %s", p)
					continue
				}
				//log.Debugf("Metric definition for \"%s\" ver %s: %s", f.Name(), pgVer.Name(), metric_sql)
				_, ok := metrics_map[f.Name()]
				if !ok {
					metrics_map[f.Name()] = make(map[decimal.Decimal]string)
				}

				metrics_map[f.Name()][d] = string(metric_sql[:])
			}
		}
	}

	return metrics_map, nil
}

func ConfigFileToMonitoredDatabases(configFilePath string) ([]MonitoredDatabase, error) {
	hostList := make([]MonitoredDatabase, 0)

	log.Debugf("Converting monitoring YAML config to MonitoredDatabase from path %s ...", configFilePath)
	yamlFile, err := ioutil.ReadFile(configFilePath)
	if err != nil {
		log.Errorf("Error reading file %s: %s", configFilePath, err)
		return hostList, err
	}
	// TODO check mod timestamp or hash, from a global "caching map"
	c := make([]MonitoredDatabase, 0) // there can be multiple configs in a single file
	err = yaml.Unmarshal(yamlFile, &c)
	if err != nil {
		log.Errorf("Unmarshaling error: %v", err)
		return hostList, err
	}
	for _, v := range c {
		log.Debugf("Found monitoring config entry: %#v", v)
		if v.IsEnabled {
			if v.Group == "" {
				v.Group = "default"
			}
			hostList = append(hostList, v)
		}
	}
	if len(hostList) == 0 {
		log.Warningf("Could not find any valid monitoring configs from file: %s", configFilePath)
	}
	return hostList, nil
}

// reads through the YAML files containing descriptions on which hosts to monitor
func ReadMonitoringConfigFromFileOrFolder(fileOrFolder string) ([]MonitoredDatabase, error) {
	hostList := make([]MonitoredDatabase, 0)

	fi, err := os.Stat(fileOrFolder)
	if err != nil {
		log.Errorf("Could not Stat() path: %s", fileOrFolder)
		return hostList, err
	}
	switch mode := fi.Mode(); {
	case mode.IsDir():
		log.Infof("Reading monitoring config from path %s ...", fileOrFolder)

		err := filepath.Walk(fileOrFolder, func(path string, info os.FileInfo, err error) error {
			if err != nil {
				return err // abort on first failure
			}
			if info.Mode().IsRegular() && (strings.HasSuffix(strings.ToLower(info.Name()), ".yaml") || strings.HasSuffix(strings.ToLower(info.Name()), ".yml")) {
				log.Debug("Found YAML config file:", info.Name())
				mdbs, err := ConfigFileToMonitoredDatabases(path)
				if err == nil {
					for _, md := range mdbs {
						hostList = append(hostList, md)
					}
				}
			}
			return nil
		})
		if err != nil {
			log.Errorf("Could not successfully Walk() path %s: %s", fileOrFolder, err)
			return hostList, err
		}
	case mode.IsRegular():
		hostList, err = ConfigFileToMonitoredDatabases(fileOrFolder)
	}

	return hostList, err
}

// "resolving" reads all the DB names from the given host/port, additionally matching/not matching specified regex patterns
func ResolveDatabasesFromConfigEntry(ce MonitoredDatabase) ([]MonitoredDatabase, error) {
	md := make([]MonitoredDatabase, 0)

	c, err := GetPostgresDBConnection("", ce.Host, ce.Port, "template1", ce.User, ce.Password, ce.SslMode)
	if err != nil {
		return md, err
	}
	defer c.Close()

	sql := `select datname::text
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
		md = append(md, MonitoredDatabase{DBUniqueName: ce.DBUniqueName + "_" + d["datname"].(string),
			DBName:        d["datname"].(string),
			Host:          ce.Host,
			Port:          ce.Port,
			User:          ce.User,
			Password:      ce.Password,
			SslMode:       ce.SslMode,
			StmtTimeout:   ce.StmtTimeout,
			Metrics:       ce.Metrics,
			PresetMetrics: ce.PresetMetrics,
			IsSuperuser:   ce.IsSuperuser,
			CustomTags:    ce.CustomTags,
			DBType:        "postgres"})
	}

	return md, err
}

// Resolves regexes if exact DBs were not specified exact
func GetMonitoredDatabasesFromMonitoringConfig(mc []MonitoredDatabase) []MonitoredDatabase {
	md := make([]MonitoredDatabase, 0)
	if mc == nil || len(mc) == 0 {
		return md
	}
	for _, e := range mc {
		//log.Debugf("Processing config item: %#v", e)
		if e.Metrics == nil && len(e.PresetMetrics) > 0 {
			mdef, ok := preset_metric_def_map[e.PresetMetrics]
			if !ok {
				log.Errorf("Failed to resolve preset config \"%s\" for \"%s\"", e.PresetMetrics, e.DBUniqueName)
				continue
			}
			e.Metrics = mdef
		}
		if len(e.DBName) == 0 || e.DBType == "postgres-continuous-discovery" {
			if e.DBType == "postgres-continuous-discovery" {
				log.Debugf("Adding \"%s\" (host=%s, port=%s) to continuous monitoring ...", e.DBUniqueName, e.Host, e.Port)
				continuousMonitoringDatabases = append(continuousMonitoringDatabases, e)
			}
			found_dbs, err := ResolveDatabasesFromConfigEntry(e)
			if err != nil {
				log.Errorf("Failed to resolve DBs for \"%s\": %s", e.DBUniqueName, err)
				continue
			}
			temp_arr := make([]string, 0)
			for _, r := range found_dbs {
				md = append(md, r)
				temp_arr = append(temp_arr, r.DBName)
			}
			log.Debugf("Resolved %d DBs with prefix \"%s\": [%s]", len(found_dbs), e.DBUniqueName, strings.Join(temp_arr, ", "))
		} else {
			md = append(md, e)
		}
	}
	return md
}

func StatsServerHandler(w http.ResponseWriter, req *http.Request) {
	jsonResponseTemplate := `
{
	"secondsFromLastSuccessfulDatastoreWrite": %d,
	"totalMetricsFetchedCounter": %d,
	"totalDatasetsFetchedCounter": %d,
	"metricPointsPerMinuteLast5MinAvg": %v,
	"metricsDropped": %d,
	"gathererUptimeSeconds": %d
}
`
	now := time.Now()
	secondsFromLastSuccessfulDatastoreWrite := int64(now.Sub(lastSuccessfulDatastoreWriteTime).Seconds())
	totalMetrics := atomic.LoadUint64(&totalMetricsFetchedCounter)
	totalDatasets := atomic.LoadUint64(&totalDatasetsFetchedCounter)
	metricsDropped := atomic.LoadUint64(&totalMetricsDroppedCounter)
	gathererUptimeSeconds := uint64(now.Sub(gathererStartTime).Seconds())
	var metricPointsPerMinute int64
	metricPointsPerMinute = atomic.LoadInt64(&metricPointsPerMinuteLast5MinAvg)
	if metricPointsPerMinute == -1 { // calculate avg. on the fly if 1st summarization hasn't happened yet
		metricPointsPerMinute = int64((totalMetrics * 60) / gathererUptimeSeconds)
	}
	io.WriteString(w, fmt.Sprintf(jsonResponseTemplate, secondsFromLastSuccessfulDatastoreWrite, totalMetrics, totalDatasets, metricPointsPerMinute, metricsDropped, gathererUptimeSeconds))
}

func StartStatsServer(port int64) {
	http.HandleFunc("/", StatsServerHandler)
	for {
		log.Errorf("Failure in StatsServerHandler:", http.ListenAndServe(fmt.Sprintf(":%d", port), nil))
		time.Sleep(time.Second * 60)
	}
}

// Calculates 1min avg metric fetching statistics for last 5min for StatsServerHandler to display
func StatsSummarizer() {
	var prevMetricsCounterValue uint64
	var currentMetricsCounterValue uint64
	ticker := time.NewTicker(time.Minute * 5)
	var lastSummarization time.Time = gathererStartTime

	for {
		select {
		case <-ticker.C:
			currentMetricsCounterValue = atomic.LoadUint64(&totalMetricsFetchedCounter)
			now := time.Now()
			atomic.StoreInt64(&metricPointsPerMinuteLast5MinAvg, int64(math.Round(float64(currentMetricsCounterValue-prevMetricsCounterValue)*60/now.Sub(lastSummarization).Seconds())))
			prevMetricsCounterValue = currentMetricsCounterValue
			lastSummarization = now
		}
	}
}

func FilterMonitoredDatabasesByGroup(monitoredDBs []MonitoredDatabase, group string) ([]MonitoredDatabase, int) {
	ret := make([]MonitoredDatabase, 0)
	groups := strings.Split(group, ",")
	for _, md := range monitoredDBs {
		// matched := false
		for _, g := range groups {
			if md.Group == g {
				ret = append(ret, md)
				break
			}
		}
	}
	return ret, len(monitoredDBs) - len(ret)
}

type Options struct {
	// Slice of bool will append 'true' each time the option
	// is encountered (can be set multiple times, like -vvv)
	Verbose              []bool `short:"v" long:"verbose" description:"Show verbose debug information" env:"PW2_VERBOSE"`
	Host                 string `long:"host" description:"PG config DB host" default:"localhost" env:"PW2_PGHOST"`
	Port                 string `short:"p" long:"port" description:"PG config DB port" default:"5432" env:"PW2_PGPORT"`
	Dbname               string `short:"d" long:"dbname" description:"PG config DB dbname" default:"pgwatch2" env:"PW2_PGDATABASE"`
	User                 string `short:"u" long:"user" description:"PG config DB user" default:"pgwatch2" env:"PW2_PGUSER"`
	Password             string `long:"password" description:"PG config DB password" env:"PW2_PGPASSWORD"`
	PgRequireSSL         string `long:"pg-require-ssl" description:"PG config DB SSL connection only" default:"false" env:"PW2_PGSSL"`
	Group                string `short:"g" long:"group" description:"Group (or groups, comma separated) for filtering which DBs to monitor. By default all are monitored" env:"PW2_GROUP"`
	Datastore            string `long:"datastore" description:"[influx|graphite|json]" default:"influx" env:"PW2_DATASTORE"`
	InfluxHost           string `long:"ihost" description:"Influx host" default:"localhost" env:"PW2_IHOST"`
	InfluxPort           string `long:"iport" description:"Influx port" default:"8086" env:"PW2_IPORT"`
	InfluxDbname         string `long:"idbname" description:"Influx DB name" default:"pgwatch2" env:"PW2_IDATABASE"`
	InfluxUser           string `long:"iuser" description:"Influx user" default:"root" env:"PW2_IUSER"`
	InfluxPassword       string `long:"ipassword" description:"Influx password" default:"root" env:"PW2_IPASSWORD"`
	InfluxSSL            string `long:"issl" description:"Influx require SSL" env:"PW2_ISSL"`
	InfluxSSLSkipVerify  string `long:"issl-skip-verify" description:"Skip Influx Cert validation i.e. allows self-signed certs" default:"true" env:"PW2_ISSL_SKIP_VERIFY"`
	InfluxHost2          string `long:"ihost2" description:"Influx host II" env:"PW2_IHOST2"`
	InfluxPort2          string `long:"iport2" description:"Influx port II" env:"PW2_IPORT2"`
	InfluxDbname2        string `long:"idbname2" description:"Influx DB name II" default:"pgwatch2" env:"PW2_IDATABASE2"`
	InfluxUser2          string `long:"iuser2" description:"Influx user II" default:"root" env:"PW2_IUSER2"`
	InfluxPassword2      string `long:"ipassword2" description:"Influx password II" default:"root" env:"PW2_IPASSWORD2"`
	InfluxSSL2           string `long:"issl2" description:"Influx require SSL II" env:"PW2_ISSL2"`
	InfluxSSLSkipVerify2 string `long:"issl-skip-verify2" description:"Skip Influx Cert validation i.e. allows self-signed certs" default:"true" env:"PW2_ISSL_SKIP_VERIFY2"`
	InfluxRetentionDays  int64  `long:"iretentiondays" description:"Retention period in days [default: 30]" env:"PW2_IRETENTIONDAYS"`
	InfluxRetentionName  string `long:"iretentionname" description:"Retention policy name. [Default: pgwatch_def_ret]" default:"pgwatch_def_ret" env:"PW2_IRETENTIONNAME"`
	GraphiteHost         string `long:"graphite-host" description:"Graphite host" env:"PW2_GRAPHITEHOST"`
	GraphitePort         string `long:"graphite-port" description:"Graphite port" env:"PW2_GRAPHITEPORT"`
	JsonStorageFile      string `long:"json-storage-file" description:"Path to file where metrics will be stored when --datastore=json, one metric set per line" env:"PW2_JSON_STORAGE_FILE"`
	// Params for running based on local config files, enabled distributed "push model" based metrics gathering. Metrics are sent directly to Influx/Graphite.
	Config            string `short:"c" long:"config" description:"File or folder of YAML files containing info on which DBs to monitor and where to store metrics" env:"PW2_CONFIG"`
	MetricsFolder     string `short:"m" long:"metrics-folder" description:"Folder of metrics definitions" env:"PW2_METRICS_FOLDER"`
	BatchingDelayMs   int64  `long:"batching-delay-ms" description:"Max milliseconds to wait for a batched metrics flush. [Default: 250]" default:"250" env:"PW2_BATCHING_MAX_DELAY_MS"`
	AdHocConnString   string `long:"adhoc-conn-str" description:"Ad-hoc mode: monitor a single Postgres DB specified by a standard Libpq connection string" env:"PW2_ADHOC_CONN_STR"`
	AdHocConfig       string `long:"adhoc-config" description:"Ad-hoc mode: a preset config name or a custom JSON config. [Default: exhaustive]" default:"exhaustive" env:"PW2_ADHOC_CONFIG"`
	AdHocUniqueName   string `long:"adhoc-name" description:"Ad-hoc mode: Unique 'dbname' for Influx. [Default: adhoc]" default:"adhoc" env:"PW2_ADHOC_NAME"`
	InternalStatsPort int64  `long:"internal-stats-port" description:"Port for inquiring monitoring status in JSON format. [Default: 8081]" default:"8081" env:"PW2_INTERNAL_STATS_PORT"`
	ConnPooling       string `long:"conn-pooling" description:"Enable re-use of metrics fetching connections [Default: off]" default:"off" env:"PW2_CONN_POOLING"`
}

var opts Options

func main() {
	parser := flags.NewParser(&opts, flags.Default)

	if _, err := parser.Parse(); err != nil {
		return
	}

	if len(opts.Verbose) >= 2 {
		logging.SetLevel(logging.DEBUG, "main")
	} else if len(opts.Verbose) == 1 {
		logging.SetLevel(logging.INFO, "main")
	} else {
		logging.SetLevel(logging.WARNING, "main")
	}
	logging.SetFormatter(logging.MustStringFormatter(`%{level:.4s} %{shortfunc}: %{message}`))

	log.Debug("opts", opts)

	// ad-hoc mode
	if len(opts.AdHocConnString) > 0 {
		if len(opts.Config) > 0 {
			log.Fatal("Conflicting flags! --adhoc-conn-str and --config cannot be both set")
		}
		if len(opts.MetricsFolder) == 0 {
			// try Docker image default file based metrics path
			_, err := ioutil.ReadDir("/pgwatch2/metrics")
			if err != nil {
				log.Fatal("--adhoc-conn-str requires also --metrics-folder param")
			}
			opts.MetricsFolder = "/pgwatch2/metrics"
		}
		if len(opts.AdHocConfig) == 0 {
			log.Fatal("--adhoc-conn-str requires also --adhoc-config param")
		}
		if len(opts.User) > 0 && len(opts.Password) > 0 {
			log.Fatal("Conflicting flags! --adhoc-conn-str and --user/--password cannot be both set")
		}
		if opts.AdHocUniqueName == "adhoc" {
			log.Warning("In ad-hoc mode: using default unique name 'adhoc' for metrics storage. use --adhoc-unique-name to override.")
		}
		adHocMode = true
	}
	// running in config file based mode?
	if len(opts.Config) > 0 || len(opts.MetricsFolder) > 0 {
		if len(opts.Config) > 0 && len(opts.MetricsFolder) == 0 {
			log.Fatal("--metrics-folder required. 'File based' operation requires presence of both --config and --metrics-folder")
		}
		if len(opts.MetricsFolder) > 0 && len(opts.Config) == 0 && !adHocMode {
			log.Fatal("--config required. 'File based' operation requires presence of both --config and --metrics-folder")
		}

		// verify that metric/config paths are readable
		_, err := ioutil.ReadDir(opts.MetricsFolder)
		if err != nil {
			log.Fatalf("Could not read path %s: %s", opts.MetricsFolder, err)
		}

		if !adHocMode {
			fi, err := os.Stat(opts.Config)
			if err != nil {
				log.Fatalf("Could not Stat() path %s: %s", opts.Config, err)
			}
			switch mode := fi.Mode(); {
			case mode.IsDir():
				_, err := ioutil.ReadDir(opts.Config)
				if err != nil {
					log.Fatalf("Could not read path %s: %s", opts.Config, err)
				}
			case mode.IsRegular():
				_, err := ioutil.ReadFile(opts.Config)
				if err != nil {
					log.Fatalf("Could not read path %s: %s", opts.Config, err)
				}
			}
		}

		fileBased = true
	} else {
		// make sure all PG params are there
		if opts.User == "" {
			opts.User = os.Getenv("USER")
		}
		if opts.Host == "" || opts.Port == "" || opts.Dbname == "" || opts.User == "" {
			fmt.Println("Check config DB parameters")
			return
		}

		InitAndTestConfigStoreConnection(opts.Host, opts.Port, opts.Dbname, opts.User, opts.Password, opts.PgRequireSSL)
	}

	// validate that input is boolean is set
	if len(strings.TrimSpace(opts.InfluxSSL)) > 0 {
		if _, err := strconv.ParseBool(opts.InfluxSSL); err != nil {
			fmt.Println("Check --issl parameter - can be of: 1, t, T, TRUE, true, True, 0, f, F, FALSE, false, False")
			return
		}
	} else {
		opts.InfluxSSL = "false"
	}
	if len(strings.TrimSpace(opts.InfluxSSL2)) > 0 {
		if _, err := strconv.ParseBool(opts.InfluxSSL2); err != nil {
			fmt.Println("Check --issl2 parameter - can be of: 1, t, T, TRUE, true, True, 0, f, F, FALSE, false, False")
			return
		}
	} else {
		opts.InfluxSSL2 = "false"
	}

	if opts.BatchingDelayMs < 0 || opts.BatchingDelayMs > 3600000 {
		log.Fatal("--batching-delay-ms must be between 0 and 3600000")
	}

	useConnPooling = StringToBoolOrFail(opts.ConnPooling)

	if opts.InternalStatsPort > 0 {
		l, err := net.Listen("tcp", fmt.Sprintf(":%d", opts.InternalStatsPort))
		if err != nil {
			log.Fatalf("Could not start the internal statistics interface on port %d. Set --internal-stats-port to an open port or to 0 to disable. Err: %v", opts.InternalStatsPort, err)
		}
		err = l.Close()
		if err != nil {
			log.Fatalf("Could not cleanly stop the temporary listener on port %d: %v", opts.InternalStatsPort, err)
		}
		log.Infof("Starting the internal statistics interface on port %d...", opts.InternalStatsPort)
		go StartStatsServer(opts.InternalStatsPort)
		go StatsSummarizer()
	}

	control_channels := make(map[string](chan ControlMessage)) // [db1+metric1]=chan
	persist_ch := make(chan []MetricStoreMessage, 10000)
	var buffered_persist_ch chan []MetricStoreMessage
	if opts.BatchingDelayMs > 0 {
		buffered_persist_ch = make(chan []MetricStoreMessage, 10000) // "staging area" for metric storage batching, when enabled
		log.Info("starting MetricsBatcher...")
		go MetricsBatcher(DATASTORE_INFLUX, opts.BatchingDelayMs, buffered_persist_ch, persist_ch)
	}

	if opts.Datastore == "graphite" {
		if opts.GraphiteHost == "" || opts.GraphitePort == "" {
			log.Fatal("--graphite-host/port needed!")
		}
		graphite_port, _ := strconv.ParseInt(opts.GraphitePort, 10, 64)
		InitGraphiteConnection(opts.GraphiteHost, int(graphite_port))
		log.Info("starting GraphitePersister...")
		go MetricsPersister(DATASTORE_GRAPHITE, persist_ch)
	} else if opts.Datastore == "influx" {
		retentionPeriod := InfluxDefaultRetentionPolicyDuration
		if opts.InfluxRetentionDays > 0 {
			retentionPeriod = opts.InfluxRetentionDays
		}
		// check connection and store connection string
		conn_str, err := InitAndTestInfluxConnection("1", opts.InfluxHost, opts.InfluxPort, opts.InfluxDbname, opts.InfluxUser,
			opts.InfluxPassword, opts.InfluxSSL, opts.InfluxSSLSkipVerify, retentionPeriod)
		if err != nil {
			log.Fatal("Could not initialize InfluxDB", err)
		}
		InfluxConnectStrings[0] = conn_str
		if len(opts.InfluxHost2) > 0 { // same check for Influx host
			if len(opts.InfluxPort2) == 0 {
				log.Fatal("Invalid Influx II connect info")
			}
			conn_str, err = InitAndTestInfluxConnection("2", opts.InfluxHost2, opts.InfluxPort2, opts.InfluxDbname2, opts.InfluxUser2,
				opts.InfluxPassword2, opts.InfluxSSL2, opts.InfluxSSLSkipVerify2, retentionPeriod)
			if err != nil {
				log.Fatal("Could not initialize InfluxDB II", err)
			}
			InfluxConnectStrings[1] = conn_str
			influx_host_count = 2
		}
		log.Info("InfluxDB connection(s) OK")

		log.Info("starting InfluxPersister...")
		go MetricsPersister(DATASTORE_INFLUX, persist_ch)
	} else if opts.Datastore == DATASTORE_JSON {
		if len(opts.JsonStorageFile) == 0 {
			log.Fatal("--datastore=json requires --json-storage-file to be set")
		}
		jsonOutFile, err := os.Create(opts.JsonStorageFile) // test file path writeability
		if err != nil {
			log.Fatalf("Could not create JSON storage file: %s", err)
		}
		err = jsonOutFile.Close()
		if err != nil {
			log.Fatal(err)
		}
		log.Warningf("In JSON ouput mode. Gathered metrics will be written to \"%s\"...", opts.JsonStorageFile)
		go MetricsPersister(DATASTORE_JSON, persist_ch)
	} else {
		log.Fatal("Unknown datastore. Check the --datastore param")
	}

	daemon.SdNotify(false, "READY=1") // Notify systemd, does nothing outside of systemd
	first_loop := true
	var monitored_dbs []MonitoredDatabase
	var last_metrics_refresh_time int64
	var err error
	var metrics map[string]map[decimal.Decimal]string

	for { //main loop
		if time.Now().Unix()-last_metrics_refresh_time > METRIC_DEFINITION_REFRESH_TIME {
			//metrics
			if fileBased {
				metrics, err = ReadMetricsFromFolder(opts.MetricsFolder, first_loop)
			} else {
				metrics, err = ReadMetricDefinitionMapFromPostgres(first_loop)
			}
			if err == nil {
				UpdateMetricDefinitionMap(metrics)
				last_metrics_refresh_time = time.Now().Unix()
			} else {
				log.Errorf("Could not refresh metric definitions: %s", err)
			}
		}

		if fileBased || adHocMode {
			pmc, err := ReadPresetMetricsConfigFromFolder(opts.MetricsFolder, false)
			if err != nil {
				if first_loop {
					log.Fatalf("Could not read preset metric config from \"%s\": %s", path.Join(opts.MetricsFolder, PRESET_CONFIG_YAML_FILE), err)
				} else {
					log.Errorf("Could not read preset metric config from \"%s\": %s", path.Join(opts.MetricsFolder, PRESET_CONFIG_YAML_FILE), err)
				}
			} else {
				preset_metric_def_map = pmc
				log.Debugf("Loaded preset metric config: %#v", pmc)
			}

			if adHocMode {
				config, ok := pmc[opts.AdHocConfig]
				if !ok {
					config = jsonTextToMap(opts.AdHocConfig)
				}
				monitored_dbs = []MonitoredDatabase{{DBUniqueName: opts.AdHocUniqueName, DBType: "postgres",
					Metrics: config}}
			} else {
				mc, err := ReadMonitoringConfigFromFileOrFolder(opts.Config)
				if err == nil {
					log.Debugf("Found %d monitoring config entries", len(mc))
					if len(opts.Group) > 0 {
						var removed_count int
						mc, removed_count = FilterMonitoredDatabasesByGroup(mc, opts.Group)
						log.Infof("Filtered out %d config entries based on --groups=%s", removed_count, opts.Group)
					}
					monitored_dbs = GetMonitoredDatabasesFromMonitoringConfig(mc)
					log.Debugf("Found %d databases to monitor from %d config items...", len(monitored_dbs), len(mc))
				} else {
					if first_loop {
						log.Fatalf("Could not read/parse monitoring config from path: %s", opts.Config)
					} else {
						log.Errorf("Could not read/parse monitoring config from path: %s", opts.Config)
					}
					time.Sleep(time.Second * time.Duration(ACTIVE_SERVERS_REFRESH_TIME))
					continue
				}
			}
		} else {
			monitored_dbs, err = GetMonitoredDatabasesFromConfigDB()
			if err != nil {
				if first_loop {
					log.Fatal("could not fetch active hosts - check config!", err)
				} else {
					log.Error("could not fetch active hosts:", err)
					time.Sleep(time.Second * time.Duration(ACTIVE_SERVERS_REFRESH_TIME))
					continue
				}
			}
		}

		UpdateMonitoredDBCache(monitored_dbs)

		if first_loop {
			first_loop = false // only used for failing when 1st config reading fails
		}

		log.Info("nr. of active hosts:", len(monitored_dbs))

		for _, host := range monitored_dbs {
			log.Debug("processing database:", host.DBUniqueName, ", config:", host.Metrics, ", custom tags:", host.CustomTags)

			host_config := host.Metrics
			db_unique := host.DBUniqueName
			db_type := host.DBType

			db_conn_limiting_channel_lock.RLock()
			_, exists := db_conn_limiting_channel[db_unique]
			db_conn_limiting_channel_lock.RUnlock()

			if !exists {
				var err error
				var ver DBVersionMapEntry

				log.Infof("new host \"%s\" found, checking connectivity...", db_unique)
				db_conn_limiting_channel_lock.Lock()
				db_conn_limiting_channel[db_unique] = make(chan bool, MAX_PG_CONNECTIONS_PER_MONITORED_DB)
				i := 0
				for i < MAX_PG_CONNECTIONS_PER_MONITORED_DB {
					log.Debugf("initializing db_conn_limiting_channel %d for [%s]", i, db_unique)
					db_conn_limiting_channel[db_unique] <- true
					i++
				}
				db_conn_limiting_channel_lock.Unlock()

				if db_type == "postgres" {
					ver, err = DBGetPGVersion(db_unique)
				} else if db_type == "pgbouncer" {
					_, err, _ = DBExecReadByDbUniqueName(db_unique, "", false, "show version")
				}
				if err != nil {
					log.Errorf("could not start metric gathering for DB \"%s\" due to connection problem: %s", db_unique, err)
					continue
				} else {
					log.Infof("Connect OK. [%s] is on version %s (in recovery: %v)", db_unique, ver.Version, ver.IsInRecovery)
				}

				if host.IsSuperuser || adHocMode {
					log.Infof("Trying to create helper functions if missing for \"%s\"...", db_unique)
					TryCreateMetricsFetchingHelpers(db_unique)
				}

				time.Sleep(time.Millisecond * 100) // not to cause a huge load spike when starting the daemon with 100+ monitored DBs
			}

			for metric := range host_config {
				interval := host_config[metric]

				metric_def_map_lock.RLock()
				_, metric_def_ok := metric_def_map[metric]
				metric_def_map_lock.RUnlock()

				var db_metric string = db_unique + ":" + metric
				_, ch_ok := control_channels[db_metric]

				if metric_def_ok && !ch_ok { // initialize a new per db/per metric control channel
					if interval > 0 {
						host_metric_interval_map[db_metric] = interval
						log.Infof("starting gatherer for [%s:%s] with interval %v s", db_unique, metric, interval)
						control_channels[db_metric] = make(chan ControlMessage, 1)
						if opts.BatchingDelayMs > 0 {
							go MetricGathererLoop(db_unique, db_type, metric, host_config, control_channels[db_metric], buffered_persist_ch)
						} else {
							go MetricGathererLoop(db_unique, db_type, metric, host_config, control_channels[db_metric], persist_ch)
						}
					}
				} else if !metric_def_ok && ch_ok {
					// metric definition files were recently removed
					log.Warning("shutting down metric", metric, "for", host.DBUniqueName)
					control_channels[db_metric] <- ControlMessage{Action: GATHERER_STATUS_STOP}
					delete(control_channels, db_metric)
				} else if !metric_def_ok {
					epoch, ok := last_sql_fetch_error.Load(metric)
					if !ok || ((time.Now().Unix() - epoch.(int64)) > 3600) { // complain only 1x per hour
						log.Warningf("metric definiton \"%s\" not found for \"%s\"", metric, db_unique)
						last_sql_fetch_error.Store(metric, time.Now().Unix())
					}
				} else {
					// check if interval has changed
					if host_metric_interval_map[db_metric] != interval {
						log.Warning("sending interval update for", db_unique, metric)
						control_channels[db_metric] <- ControlMessage{Action: GATHERER_STATUS_START, Config: host_config}
						host_metric_interval_map[db_metric] = interval
					}
				}
			}
		}

		// loop over existing channels and stop workers if DB or metric removed from config
		log.Debug("checking if any workers need to be shut down...")
		control_channel_list := make([]string, len(control_channels))
		i := 0
		for key := range control_channels {
			control_channel_list[i] = key
			i++
		}
		gatherers_shut_down := 0

	next_chan:
		for _, db_metric := range control_channel_list {
			splits := strings.Split(db_metric, ":")
			db := splits[0]
			metric := splits[1]

			for _, host := range monitored_dbs {
				if host.DBUniqueName == db {
					host_config := host.Metrics

					for metric_key := range host_config {
						if metric_key == metric && host_config[metric_key] > 0 {
							continue next_chan
						}
					}
				}
			}

			log.Infof("shutting down gatherer for [%s:%s] ...", db, metric)
			control_channels[db_metric] <- ControlMessage{Action: GATHERER_STATUS_STOP}
			delete(control_channels, db_metric)
			log.Infof("control channel for [%s:%s] deleted", db, metric)
			gatherers_shut_down++
		}
		if gatherers_shut_down > 0 {
			log.Warningf("sent STOP message to %d gatherers (it might take some minutes for them to stop though)", gatherers_shut_down)
		}
		log.Debugf("main sleeping %ds...", ACTIVE_SERVERS_REFRESH_TIME)
		time.Sleep(time.Second * time.Duration(ACTIVE_SERVERS_REFRESH_TIME))
	}

}
