package main

import (
	"container/list"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/influxdata/influxdb/client/v2"
	"github.com/jessevdk/go-flags"
	"github.com/jmoiron/sqlx"
	_ "github.com/lib/pq"
	"github.com/marpaia/graphite-golang"
	"github.com/op/go-logging"
	"github.com/shopspring/decimal"
)

type MonitoredDatabase struct {
	DBUniqueName string
	Host         string
	Port         string
	DBName       string
	User         string
	Password     string
	SslMode      string
	Metrics      map[string]int
	StmtTimeout  int64
	DBType       string
}

type ControlMessage struct {
	Action string // START, STOP, PAUSE
	Config map[string]interface{}
}

type MetricFetchMessage struct {
	DBUniqueName string
	MetricName   string
	DBType       string
}

type MetricStoreMessage struct {
	DBUniqueName string
	DBType       string
	MetricName   string
	Data         [](map[string]interface{})
}

type ChangeDetectionResults struct { // for passing around DDL/index/config change detection results
	Created int
	Altered int
	Dropped int
}

type DBVersionMapEntry struct {
	LastCheckedOn time.Time
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

var configDb *sqlx.DB
var graphiteConnection *graphite.Graphite
var log = logging.MustGetLogger("main")
var metric_def_map map[string]map[decimal.Decimal]string
var metric_def_map_lock = sync.RWMutex{}
var host_metric_interval_map = make(map[string]float64) // [db1_metric] = 30
var db_pg_version_map = make(map[string]DBVersionMapEntry)
var db_pg_version_map_lock = sync.RWMutex{}
var InfluxDefaultRetentionPolicyDuration int64 = 90 // 90 days of monitoring data will be kept around. can be adjusted later on influx side if needed
var monitored_db_cache map[string]map[string]interface{}
var monitored_db_cache_lock sync.RWMutex
var metric_fetching_channels = make(map[string](chan MetricFetchMessage)) // [db1unique]=chan
var metric_fetching_channels_lock = sync.RWMutex{}
var influx_host_count = 1
var InfluxConnectStrings [2]string // Max. 2 Influx metrics stores currently supported
// secondary Influx meant for HA or Grafana load balancing for 100+ instances with lots of alerts

func GetPostgresDBConnection(host, port, dbname, user, password, sslmode string) (*sqlx.DB, error) {
	var err error
	var db *sqlx.DB

	//log.Debug("Connecting to: ", host, port, dbname, user, password)

	db, err = sqlx.Open("postgres", fmt.Sprintf("host=%s port=%s dbname=%s sslmode=%s user=%s password=%s",
		host, port, dbname, sslmode, user, password))

	if err != nil {
		log.Error("could not open configDb connection", err)
	}
	return db, err
}

func InitAndTestConfigStoreConnection(host, port, dbname, user, password string) {
	var err error

	configDb, err = GetPostgresDBConnection(host, port, dbname, user, password, "disable") // configDb is used by the main thread only
	if err != nil {
		log.Fatal("could not open configDb connection! exit.")
	}

	err = configDb.Ping()

	if err != nil {
		log.Fatal("could not ping configDb! exit.", err)
	} else {
		log.Info("connect to configDb OK!")
	}
}

func DBExecRead(conn *sqlx.DB, host_ident, sql string, args ...interface{}) ([](map[string]interface{}), error) {
	ret := make([]map[string]interface{}, 0)

	rows, err := conn.Queryx(sql, args...)
	if err != nil {
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

func DBExecReadByDbUniqueName(dbUnique string, sql string, args ...interface{}) ([](map[string]interface{}), error) {
	if strings.TrimSpace(sql) == "" {
		return nil, errors.New("empty SQL")
	}
	md, err := GetMonitoredDatabaseByUniqueName(dbUnique)
	if err != nil {
		return nil, err
	}
	if md.DBType == "pgbouncer" {
		md.DBName = "pgbouncer"
	}
	conn, err := GetPostgresDBConnection(md.Host, md.Port, md.DBName, md.User, md.Password, md.SslMode) // TODO pooling
	if err != nil {
		return nil, err
	}
	defer conn.Close()

	_, err = DBExecRead(conn, dbUnique, fmt.Sprintf("SET statement_timeout TO '%ds'", md.StmtTimeout))
	if err != nil {
		return nil, err
	}

	return DBExecRead(conn, dbUnique, sql, args...)
}

func GetAllActiveHostsFromConfigDB() ([](map[string]interface{}), error) {
	sql := `
		select
		  md_unique_name, md_dbtype, md_hostname, md_port, md_dbname, md_user, coalesce(md_password, '') as md_password,
		  coalesce(pc_config, md_config)::text as md_config, md_statement_timeout_seconds, md_sslmode, md_is_superuser
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
	} else {
		UpdateMonitoredDBCache(data) // cache used by workers
	}
	return data, err
}

func SendToInflux(connect_str, conn_id, dbname, measurement string, data [](map[string]interface{})) error {
	if data == nil || len(data) == 0 {
		return nil
	}
	log.Debug("SendToInflux", conn_id, "data[0] of ", len(data), ":", data[0])
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
	for _, dr := range data {
		// Create a point and add to batch
		var epoch_time time.Time
		var epoch_ns int64
		tags := make(map[string]string)
		fields := make(map[string]interface{})

		tags["dbname"] = dbname

		for k, v := range dr {
			if v == nil || v == "" {
				continue // not storing NULLs
			}
			if k == EPOCH_COLUMN_NAME {
				epoch_ns = v.(int64)
			} else if strings.HasPrefix(k, "tag_") {
				tag := k[4:]
				tags[tag] = fmt.Sprintf("%s", v)
			} else {
				fields[k] = v
			}
		}

		if epoch_ns == 0 {
			if !ts_warning_printed && measurement != "pgbouncer_stats" {
				log.Warning("No timestamp_ns found, server time will be used. measurement:", measurement)
				ts_warning_printed = true
			}
			epoch_time = time.Now()
		} else {
			epoch_time = time.Unix(0, epoch_ns)
		}

		pt, err := client.NewPoint(measurement, tags, fields, epoch_time)

		if err != nil {
			log.Error("NewPoint failed:", err)
			continue
		}

		bp.AddPoint(pt)
		rows_batched += 1
	}
	t1 := time.Now()
	err = c.Write(bp)
	t_diff := time.Now().Sub(t1)
	if err == nil {
		log.Info(fmt.Sprintf("wrote %d/%d rows to InfluxDB %s for [%s:%s] in %dus", rows_batched, len(data),
			conn_id, dbname, measurement, t_diff.Nanoseconds()/1000))
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
	log.Debug(fmt.Sprintf("Writing %d rows to Graphite", len(data)))

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
	t1 := time.Now().UnixNano()
	err := graphiteConnection.SendMetrics(metrics)
	t2 := time.Now().UnixNano()
	if err != nil {
		log.Error("could not send metric to Graphite:", err)
	}
	log.Debug("Sent in ", (t2-t1)/1000, "us")

	return err
}

func GetMonitoredDatabaseByUniqueName(name string) (MonitoredDatabase, error) {
	monitored_db_cache_lock.RLock()
	defer monitored_db_cache_lock.RUnlock()
	_, exists := monitored_db_cache[name]
	if !exists {
		return MonitoredDatabase{}, errors.New("md_unique_name not found")
	}
	md := MonitoredDatabase{
		Host:        monitored_db_cache[name]["md_hostname"].(string),
		Port:        monitored_db_cache[name]["md_port"].(string),
		DBName:      monitored_db_cache[name]["md_dbname"].(string),
		User:        monitored_db_cache[name]["md_user"].(string),
		Password:    monitored_db_cache[name]["md_password"].(string),
		SslMode:     monitored_db_cache[name]["md_sslmode"].(string),
		StmtTimeout: monitored_db_cache[name]["md_statement_timeout_seconds"].(int64),
		DBType:      monitored_db_cache[name]["md_dbtype"].(string),
	}
	return md, nil
}

func UpdateMonitoredDBCache(data [](map[string]interface{})) error {
	if data == nil || len(data) == 0 {
		return nil
	}

	monitored_db_cache_new := make(map[string]map[string]interface{})

	for _, row := range data {
		monitored_db_cache_new[row["md_unique_name"].(string)] = row
	}

	monitored_db_cache_lock.Lock()
	monitored_db_cache = monitored_db_cache_new
	monitored_db_cache_lock.Unlock()

	return nil
}

func ProcessRetryQueue(data_source, conn_str, conn_ident string, retry_queue *list.List, limit int) error {
	var err error
	iterations_done := 0

	for retry_queue.Len() > 0 { // send over the whole re-try queue at once if connection works
		log.Info("Processing InfluxDB retry_queue", conn_ident, ". Items in retry_queue: ", retry_queue.Len())
		msg := retry_queue.Back().Value.(MetricStoreMessage)

		if data_source == DATASTORE_INFLUX {
			err = SendToInflux(conn_str, conn_ident, msg.DBUniqueName, msg.MetricName, msg.Data)
		} else if data_source == DATASTORE_GRAPHITE {
			err = SendToGraphite(msg.DBUniqueName, msg.MetricName, msg.Data)
		} else {
			log.Fatal("Invalid datastore:", data_source)
		}
		if err != nil {
			if data_source == DATASTORE_INFLUX && strings.Contains(err.Error(), "unable to parse") {
				log.Error(fmt.Sprintf("Dropping metric [%s:%s] as Influx is unable to parse the data: %s",
					msg.DBUniqueName, msg.MetricName, msg.Data)) // ignore data points consisting of anything else than strings and floats
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

// TODO batching of mutiple datasets
func MetricsPersister(data_store string, storage_ch <-chan MetricStoreMessage) {
	var last_try = make([]time.Time, influx_host_count)          // if Influx errors out, don't retry before 10s
	var last_drop_warning = make([]time.Time, influx_host_count) // log metric points drops every 10s to not overflow logs in case Influx is down for longer
	var retry_queues = make([]*list.List, influx_host_count)     // separate queues for all Influx hosts
	var in_error = make([]bool, influx_host_count)
	var points_dropped = make([]int64, influx_host_count)
	var err error

	for i := 0; i < influx_host_count; i++ {
		retry_queues[i] = list.New()
	}

	for {
		select {
		case msg := <-storage_ch:
			for i, retry_queue := range retry_queues {

				retry_queue_length := retry_queue.Len()

				if retry_queue_length > 0 {
					if retry_queue_length == PERSIST_QUEUE_MAX_SIZE {
						retry_queue.Remove(retry_queue.Back())
						points_dropped[i] += 1
						if last_drop_warning[i].IsZero() || last_drop_warning[i].Before(time.Now().Add(time.Second*-10)) {
							log.Warning("Dropped", points_dropped, "oldest data points from queue", i, "as PERSIST_QUEUE_MAX_SIZE =", PERSIST_QUEUE_MAX_SIZE, "exceeded")
							last_drop_warning[i] = time.Now()
							points_dropped[i] = 0
						}
					}
					retry_queue.PushFront(msg)
				} else {
					if data_store == DATASTORE_INFLUX {
						err = SendToInflux(InfluxConnectStrings[i], strconv.Itoa(i), msg.DBUniqueName, msg.MetricName, msg.Data)
					} else if data_store == DATASTORE_GRAPHITE {
						err = SendToGraphite(msg.DBUniqueName, msg.MetricName, msg.Data)
					} else {
						log.Fatal("Invalid datastore:", data_store)
					}
					last_try[i] = time.Now()
					if err != nil {
						if strings.Contains(err.Error(), "unable to parse") {
							log.Error(fmt.Sprintf("Dropping metric [%s:%s] as Influx is unable to parse the data: %s",
								msg.DBUniqueName, msg.MetricName, msg.Data)) // ignore data points consisting of anything else than strings and floats
						} else {
							log.Error(fmt.Sprintf("Failed to write into datastore %d: %s", i, err))
							in_error[i] = true
							retry_queue.PushFront(msg)
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

func DBGetPGVersion(dbUnique string) (decimal.Decimal, error) {
	var ver DBVersionMapEntry
	var ok bool
	sql := `
		select (regexp_matches(
			regexp_replace(current_setting('server_version'), '(beta|devel).*', '', 'g'),
			E'\\d+\\.?\\d+?')
			)[1]::text as ver;
	`

	db_pg_version_map_lock.RLock()
	ver, ok = db_pg_version_map[dbUnique]
	db_pg_version_map_lock.RUnlock()

	if ok && ver.LastCheckedOn.After(time.Now().Add(time.Minute*-2)) { // use cached version for 2 min
		log.Debug(fmt.Sprintf("using cached postgres version %s for %s", ver.Version.String(), dbUnique))
		return ver.Version, nil
	} else {
		log.Debug("determining DB version for", dbUnique)
		data, err := DBExecReadByDbUniqueName(dbUnique, sql)
		if err != nil {
			log.Error("DBGetPGVersion failed", err)
			return ver.Version, err
		}
		ver.Version, _ = decimal.NewFromString(data[0]["ver"].(string))
		ver.LastCheckedOn = time.Now()
		log.Info(fmt.Sprintf("%s is on version %s", dbUnique, ver.Version))

		db_pg_version_map_lock.Lock()
		db_pg_version_map[dbUnique] = ver
		db_pg_version_map_lock.Unlock()
	}
	return ver.Version, nil
}

// Need to define a sort interface as Go doesn't have support for Numeric/Decimal
type Decimal []decimal.Decimal

func (a Decimal) Len() int           { return len(a) }
func (a Decimal) Swap(i, j int)      { a[i], a[j] = a[j], a[i] }
func (a Decimal) Less(i, j int) bool { return a[i].LessThan(a[j]) }

// assumes upwards compatibility for versions
func GetSQLForMetricPGVersion(metric string, pgVer decimal.Decimal) (string, error) {
	var keys []decimal.Decimal

	metric_def_map_lock.RLock()
	defer metric_def_map_lock.RUnlock()

	_, ok := metric_def_map[metric]
	if !ok || len(metric_def_map[metric]) == 0 {
		log.Error("metric", metric, "not found")
		return "", errors.New("metric SQL not found")
	}

	for k := range metric_def_map[metric] {
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

	return metric_def_map[metric][best_ver], nil
}

func DetectSprocChanges(dbUnique string, db_pg_version decimal.Decimal, storage_ch chan<- MetricStoreMessage, host_state map[string]map[string]string) ChangeDetectionResults {
	detected_changes := make([](map[string]interface{}), 0)
	var first_run bool
	var change_counts ChangeDetectionResults

	log.Debug("checking for sproc changes...")
	if _, ok := host_state["sproc_hashes"]; !ok {
		first_run = true
		host_state["sproc_hashes"] = make(map[string]string)
	}

	sql, err := GetSQLForMetricPGVersion("sproc_hashes", db_pg_version)
	if err != nil {
		log.Error("could not get sproc_hashes sql:", err)
		return change_counts
	}

	data, err := DBExecReadByDbUniqueName(dbUnique, sql)
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
		storage_ch <- MetricStoreMessage{DBUniqueName: dbUnique, MetricName: "sproc_changes", Data: detected_changes}
	}

	return change_counts
}

func DetectTableChanges(dbUnique string, db_pg_version decimal.Decimal, storage_ch chan<- MetricStoreMessage, host_state map[string]map[string]string) ChangeDetectionResults {
	detected_changes := make([](map[string]interface{}), 0)
	var first_run bool
	var change_counts ChangeDetectionResults

	log.Debug("checking for table changes...")
	if _, ok := host_state["table_hashes"]; !ok {
		first_run = true
		host_state["table_hashes"] = make(map[string]string)
	}

	sql, err := GetSQLForMetricPGVersion("table_hashes", db_pg_version)
	if err != nil {
		log.Error("could not get table_hashes sql:", err)
		return change_counts
	}

	data, err := DBExecReadByDbUniqueName(dbUnique, sql)
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
		storage_ch <- MetricStoreMessage{DBUniqueName: dbUnique, MetricName: "table_changes", Data: detected_changes}
	}

	return change_counts
}

func DetectIndexChanges(dbUnique string, db_pg_version decimal.Decimal, storage_ch chan<- MetricStoreMessage, host_state map[string]map[string]string) ChangeDetectionResults {
	detected_changes := make([](map[string]interface{}), 0)
	var first_run bool
	var change_counts ChangeDetectionResults

	log.Debug("checking for index changes...")
	if _, ok := host_state["index_hashes"]; !ok {
		first_run = true
		host_state["index_hashes"] = make(map[string]string)
	}

	sql, err := GetSQLForMetricPGVersion("index_hashes", db_pg_version)
	if err != nil {
		log.Error("could not get index_hashes sql:", err)
		return change_counts
	}

	data, err := DBExecReadByDbUniqueName(dbUnique, sql)
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
		storage_ch <- MetricStoreMessage{DBUniqueName: dbUnique, MetricName: "index_changes", Data: detected_changes}
	}

	return change_counts
}

func DetectConfigurationChanges(dbUnique string, db_pg_version decimal.Decimal, storage_ch chan<- MetricStoreMessage, host_state map[string]map[string]string) ChangeDetectionResults {
	detected_changes := make([](map[string]interface{}), 0)
	var first_run bool
	var change_counts ChangeDetectionResults

	log.Debug("checking for pg_settings changes...")
	if _, ok := host_state["configuration_hashes"]; !ok {
		first_run = true
		host_state["configuration_hashes"] = make(map[string]string)
	}

	sql, err := GetSQLForMetricPGVersion("configuration_hashes", db_pg_version)
	if err != nil {
		log.Error("could not get index_hashes sql:", err)
		return change_counts
	}

	data, err := DBExecReadByDbUniqueName(dbUnique, sql)
	if err != nil {
		log.Error("could not read configuration_hashes from monitored host:", dbUnique, ", err:", err)
		return change_counts
	}

	for _, dr := range data {
		obj_ident := dr["tag_setting"].(string)
		prev_hash, ok := host_state["configuration_hashes"][obj_ident]
		if ok { // we have existing state
			if prev_hash != dr["value"].(string) {
				log.Warning(fmt.Sprintf("detected settings change: %s = %s (prev: %s)",
					dr["tag_setting"], dr["value"], prev_hash))
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
		storage_ch <- MetricStoreMessage{DBUniqueName: dbUnique, MetricName: "configuration_changes", Data: detected_changes}
	}

	return change_counts
}

func CheckForPGObjectChangesAndStore(dbUnique string, db_pg_version decimal.Decimal, storage_ch chan<- MetricStoreMessage, host_state map[string]map[string]string) {
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
		storage_ch <- MetricStoreMessage{DBUniqueName: dbUnique, DBType: "postgres", MetricName: "object_changes", Data: detected_changes_summary}
	}
}

func FilterPgbouncerData(data []map[string]interface{}, database_to_keep string) []map[string]interface{} {
	filtered_data := make([]map[string]interface{}, 0)
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
	return filtered_data
}

func MetricsFetcher(fetch_msg <-chan MetricFetchMessage, storage_ch chan<- MetricStoreMessage) {
	host_state := make(map[string]map[string]string) // sproc_hashes: {"sproc_name": "md5..."}
	var db_pg_version decimal.Decimal
	var err error

	for {
		select {
		case msg := <-fetch_msg:
			if msg.DBType == "postgres" {
				// DB version lookup
				db_pg_version, err = DBGetPGVersion(msg.DBUniqueName)
				if err != nil {
					log.Error("failed to fetch pg version for ", msg.DBUniqueName, msg.MetricName, err)
					continue
				}
			} else if msg.DBType == "pgbouncer" {
				db_pg_version = decimal.Decimal{} // version is 0.0 for all pgbouncer sql per convention
				// as surprisingly pgbouncer 'show version' outputs it as 'NOTICE'
				// which cannot be accessed from Go lib/pg
			}

			sql, err := GetSQLForMetricPGVersion(msg.MetricName, db_pg_version)
			//log.Debug("SQL", sql)
			if err != nil {
				log.Error(fmt.Sprintf("Failed to get SQL for metric '%s', version '%s'", msg.MetricName, db_pg_version))
				continue
			}

			if msg.MetricName == "change_events" { // special handling, multiple queries + stateful
				CheckForPGObjectChangesAndStore(msg.DBUniqueName, db_pg_version, storage_ch, host_state)
			} else {
				t1 := time.Now().UnixNano()
				data, err := DBExecReadByDbUniqueName(msg.DBUniqueName, sql)
				t2 := time.Now().UnixNano()
				if err != nil {
					log.Error(fmt.Sprintf("failed to fetch metrics for '%s', metric '%s': %s", msg.DBUniqueName, msg.MetricName, err))
				} else {
					log.Info(fmt.Sprintf("fetched %d rows for [%s:%s] in %dus", len(data), msg.DBUniqueName, msg.MetricName, (t2-t1)/1000))
					if msg.MetricName == "pgbouncer_stats" { // clean unwanted pgbouncer pool stats here as not possible in SQL
						md, err := GetMonitoredDatabaseByUniqueName(msg.DBUniqueName)
						if err != nil {
							log.Error(fmt.Sprintf("could not get monitored DB details for %s: %s", msg.DBUniqueName, err))
						}
						data = FilterPgbouncerData(data, md.DBName)
					}
					if len(data) > 0 {
						storage_ch <- MetricStoreMessage{DBUniqueName: msg.DBUniqueName, MetricName: msg.MetricName, Data: data}
					}
				}
			}

		}

	}
}

func ForwardQueryMessageToDBUniqueFetcher(msg MetricFetchMessage) {
	// Currently only 1 fetcher per DB but option to configure more parallel connections would be handy
	log.Debug("got MetricFetchMessage:", msg)
	metric_fetching_channels_lock.RLock()
	q_ch, _ := metric_fetching_channels[msg.DBUniqueName]
	metric_fetching_channels_lock.RUnlock()
	q_ch <- msg
}

// ControlMessage notifies of shutdown + interval change
func MetricGathererLoop(dbUniqueName, dbType, metricName string, config_map map[string]interface{}, control_ch <-chan ControlMessage) {
	config := config_map
	interval := config[metricName].(float64)
	running := true
	ticker := time.NewTicker(time.Second * time.Duration(interval))

	for {
		if running {
			ForwardQueryMessageToDBUniqueFetcher(MetricFetchMessage{DBUniqueName: dbUniqueName, MetricName: metricName, DBType: dbType})
		}

		select {
		case msg := <-control_ch:
			log.Debug("got control msg", dbUniqueName, metricName, msg)
			if msg.Action == "START" {
				config = msg.Config
				interval = config[metricName].(float64)
				ticker = time.NewTicker(time.Second * time.Duration(interval))
				if !running {
					running = true
					log.Info("started MetricGathererLoop for ", dbUniqueName, metricName, " interval:", interval)
				}
			} else if msg.Action == "STOP" && running {
				log.Info("exiting MetricGathererLoop for ", dbUniqueName, metricName, " interval:", interval)
				return
			} else if msg.Action == "PAUSE" && running {
				log.Info("pausing MetricGathererLoop for ", dbUniqueName, metricName, " interval:", interval)
				running = false
			}
		case <-ticker.C:
			log.Debug(fmt.Sprintf("MetricGathererLoop for %s:%s slept for %s", dbUniqueName, metricName, time.Second*time.Duration(interval)))
		}

	}
}

func UpdateMetricDefinitionMapFromPostgres() {
	metric_def_map_new := make(map[string]map[decimal.Decimal]string)
	sql := "select m_name, m_pg_version_from::text, m_sql from pgwatch2.metric where m_is_active"
	data, err := DBExecRead(configDb, "configDb", sql)
	if err != nil {
		log.Error(err)
		return
	}
	if len(data) == 0 {
		log.Warning("no metric definitions found from config DB")
		return
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

	metric_def_map_lock.Lock()
	metric_def_map = metric_def_map_new
	metric_def_map_lock.Unlock()
	log.Debug("metric_def_map:", metric_def_map)
	log.Info("metrics definitions refreshed from config DB. nr. found:", len(metric_def_map_new))

}

func jsonTextToMap(jsonText string) map[string]interface{} {

	var host_config map[string]interface{}
	if err := json.Unmarshal([]byte(jsonText), &host_config); err != nil {
		panic(err)
	}
	return host_config
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

func InitAndTestInfluxConnection(HostId, InfluxHost, InfluxPort, InfluxDbname, InfluxUser, InfluxPassword string, InfluxSSL bool, RetentionPeriod int64) (string, error) {
	log.Info(fmt.Sprintf("Testing Influx connection to host %s: %s, port: %s, DB: %s", HostId, InfluxHost, InfluxPort, InfluxDbname))
	var connect_string string

	if InfluxSSL {
		connect_string = fmt.Sprintf("https://%s:%s", InfluxHost, InfluxPort)
	} else {
		connect_string = fmt.Sprintf("http://%s:%s", InfluxHost, InfluxPort)
	}

	// Make client
	c, err := client.NewHTTPClient(client.HTTPConfig{
		Addr:     connect_string,
		Username: InfluxUser,
		Password: InfluxPassword,
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

	log.Warning(fmt.Sprintf("Database '%s' not found! Creating with %d retention...", InfluxDbname, RetentionPeriod))
	isql := fmt.Sprintf("CREATE DATABASE %s WITH DURATION %dd REPLICATION 1 SHARD DURATION 3d NAME pgwatch_def_ret", InfluxDbname, RetentionPeriod)
	res, err = queryDB(c, isql)
	if err != nil {
		log.Fatal(err)
	} else {
		log.Info("Database 'pgwatch2' created on host", fmt.Sprintf("%s:%s", InfluxHost, InfluxPort))
	}

	return connect_string, nil
}

func DoesFunctionExists(dbUnique, functionName string) bool {
	log.Debug("Checking for function existance", dbUnique, functionName)
	sql := fmt.Sprintf("select 1 from pg_proc join pg_namespace n on pronamespace = n.oid where proname = '%s' and n.nspname = 'public'", functionName)
	data, err := DBExecReadByDbUniqueName(dbUnique, sql)
	if err != nil {
		log.Error("Failed to check for function existance", dbUnique, functionName, err)
		return false
	}
	if len(data) > 0 {
		log.Debug(fmt.Sprintf("Function %s exists on %s", functionName, dbUnique))
		return true
	}
	return false
}

// Called once on daemon startup to try to create "metric fething helper" functions automatically
func TryCreateMetricsFetchingHelpers(dbUnique string) {
	db_pg_version, err := DBGetPGVersion(dbUnique)
	if err != nil {
		log.Error(fmt.Sprintf("Failed to fetch pg version for \"%s\": %s", dbUnique, err))
		return
	}

	sql_helpers := "select distinct m_name from metric where m_is_active and m_is_helper" // m_name is a helper function name
	data, err := DBExecRead(configDb, "configDb", sql_helpers)
	if err != nil {
		log.Error(err)
		return
	}

	for _, row := range data {
		metric := row["m_name"].(string)

		if !DoesFunctionExists(dbUnique, metric) {

			log.Debug("Trying to create metric fetching helpers for", dbUnique, metric)
			sql, err := GetSQLForMetricPGVersion(metric, db_pg_version)
			if err != nil {
				_, err := DBExecReadByDbUniqueName(dbUnique, sql)
				if err != nil {
					log.Warning("Failed to create a metric fetching helper for", dbUnique, metric)
					log.Warning(err)
				} else {
					log.Debug("Successfully created metric fetching helper for", dbUnique, metric)
				}
			} else {
				log.Warning("Could not find query text for", dbUnique, metric)
			}
		}
	}
}

type Options struct {
	// Slice of bool will append 'true' each time the option
	// is encountered (can be set multiple times, like -vvv)
	Verbose             []bool `short:"v" long:"verbose" description:"Show verbose debug information" env:"PW2_VERBOSE"`
	Host                string `long:"host" description:"PG config DB host" default:"localhost" env:"PW2_PGHOST"`
	Port                string `short:"p" long:"port" description:"PG config DB port" default:"5432" env:"PW2_PGPORT"`
	Dbname              string `short:"d" long:"dbname" description:"PG config DB dbname" default:"pgwatch2" env:"PW2_PGDATABASE"`
	User                string `short:"u" long:"user" description:"PG config DB host" default:"pgwatch2" env:"PW2_PGUSER"`
	Password            string `long:"password" description:"PG config DB password" env:"PW2_PGPASSWORD"`
	Datastore           string `long:"datastore" description:"[influx|graphite]" default:"influx" env:"PW2_DATASTORE"`
	InfluxHost          string `long:"ihost" description:"Influx host" default:"localhost" env:"PW2_IHOST"`
	InfluxPort          string `long:"iport" description:"Influx port" default:"8086" env:"PW2_IPORT"`
	InfluxDbname        string `long:"idbname" description:"Influx DB name" default:"pgwatch2" env:"PW2_IDATABASE"`
	InfluxUser          string `long:"iuser" description:"Influx user" default:"root" env:"PW2_IUSER"`
	InfluxPassword      string `long:"ipassword" description:"Influx password" default:"root" env:"PW2_IPASSWORD"`
	InfluxSSL           bool   `long:"issl" description:"Influx require SSL" env:"PW2_ISSL"`
	InfluxHost2         string `long:"ihost2" description:"Influx host II" env:"PW2_IHOST2"`
	InfluxPort2         string `long:"iport2" description:"Influx port II" env:"PW2_IPORT2"`
	InfluxDbname2       string `long:"idbname2" description:"Influx DB name II" default:"pgwatch2" env:"PW2_IDATABASE2"`
	InfluxUser2         string `long:"iuser2" description:"Influx user II" default:"root" env:"PW2_IUSER2"`
	InfluxPassword2     string `long:"ipassword2" description:"Influx password II" default:"root" env:"PW2_IPASSWORD2"`
	InfluxSSL2          bool   `long:"issl2" description:"Influx require SSL II" env:"PW2_ISSL2"`
	InfluxRetentionDays int64  `long:"iretentiondays" description:"Retention period in days [90 default]" env:"PW2_IRETENTIONDAYS"`
	GraphiteHost        string `long:"graphite-host" description:"Graphite host" env:"PW2_GRAPHITEHOST"`
	GraphitePort        string `long:"graphite-port" description:"Graphite port" env:"PW2_GRAPHITEPORT"`
	//File           string `short:"f" long:"file" description:"Sqlite3 config DB file"`
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

	// make sure all PG params are there
	if opts.User == "" {
		opts.User = os.Getenv("USER")
	}
	if opts.Host == "" || opts.Port == "" || opts.Dbname == "" || opts.User == "" {
		fmt.Println("Check config DB parameters")
		return
	}

	InitAndTestConfigStoreConnection(opts.Host, opts.Port, opts.Dbname, opts.User, opts.Password)

	control_channels := make(map[string](chan ControlMessage)) // [db1+metric1]=chan
	persist_ch := make(chan MetricStoreMessage, 1000)

	if opts.Datastore == "graphite" {
		if opts.GraphiteHost == "" || opts.GraphitePort == "" {
			log.Fatal("--graphite-host/port needed!")
		}
		graphite_port, _ := strconv.ParseInt(opts.GraphitePort, 10, 64)
		InitGraphiteConnection(opts.GraphiteHost, int(graphite_port))
		log.Info("starting GraphitePersister...")
		go MetricsPersister(DATASTORE_GRAPHITE, persist_ch)
	} else {
		retentionPeriod := InfluxDefaultRetentionPolicyDuration
		if opts.InfluxRetentionDays > 0 {
			retentionPeriod = opts.InfluxRetentionDays
		}
		// check connection and store connection string
		conn_str, err := InitAndTestInfluxConnection("1", opts.InfluxHost, opts.InfluxPort, opts.InfluxDbname, opts.InfluxUser,
			opts.InfluxPassword, opts.InfluxSSL, retentionPeriod)
		if err != nil {
			log.Fatal("Could not initialize InfluxDB", err)
		}
		InfluxConnectStrings[0] = conn_str
		if len(opts.InfluxHost2) > 0 { // same check for Influx host
			if len(opts.InfluxPort2) == 0 {
				log.Fatal("Invalid Influx II connect info")
			}
			conn_str, err = InitAndTestInfluxConnection("2", opts.InfluxHost2, opts.InfluxPort2, opts.InfluxDbname2, opts.InfluxUser2,
				opts.InfluxPassword2, opts.InfluxSSL2, retentionPeriod)
			if err != nil {
				log.Fatal("Could not initialize InfluxDB II", err)
			}
			InfluxConnectStrings[1] = conn_str
			influx_host_count = 2
		}
		log.Info("InfluxDB connection(s) OK")
		log.Info("starting InfluxPersister...")
		go MetricsPersister(DATASTORE_INFLUX, persist_ch)
	}

	first_loop := true
	var last_metrics_refresh_time int64

	for { //main loop
		if time.Now().Unix()-last_metrics_refresh_time > METRIC_DEFINITION_REFRESH_TIME {
			log.Info("updating metrics definitons from ConfigDB...")
			UpdateMetricDefinitionMapFromPostgres()
			last_metrics_refresh_time = time.Now().Unix()
		}
		monitored_dbs, err := GetAllActiveHostsFromConfigDB()
		if err != nil {
			if first_loop {
				log.Fatal("could not fetch active hosts - check config!", err)
			} else {
				log.Error("could not fetch active hosts:", err)
				time.Sleep(time.Second * time.Duration(ACTIVE_SERVERS_REFRESH_TIME))
				continue
			}
		}
		if first_loop {
			first_loop = false // only used for failing when 1st config reading fails
		}

		log.Info("nr. of active hosts:", len(monitored_dbs))

		for _, host := range monitored_dbs {
			log.Info("processing database", host["md_unique_name"], "config:", host["md_config"])

			host_config := jsonTextToMap(host["md_config"].(string))
			db_unique := host["md_unique_name"].(string)
			db_type := host["md_dbtype"].(string)

			// make sure query channel for every DBUnique exists. means also max 1 concurrent query for 1 DB
			metric_fetching_channels_lock.RLock()
			_, exists := metric_fetching_channels[db_unique]
			metric_fetching_channels_lock.RUnlock()
			if !exists {
				var err error

				log.Info(fmt.Sprintf("new host \"%s\"found, checking connectivity...", db_unique))
				if db_type == "postgres" {
					_, err = DBExecReadByDbUniqueName(db_unique, "select 1") // test connectivity
				} else if db_type == "pgbouncer" {
					_, err = DBExecReadByDbUniqueName(db_unique, "show version")
				}
				if err != nil {
					log.Error(fmt.Sprintf("could not start metric gathering for DB \"%s\" due to connection problem: %s", db_unique, err))
					continue
				}
				if host["md_is_superuser"].(bool) {
					TryCreateMetricsFetchingHelpers(db_unique)
				}
				metric_fetching_channels_lock.Lock()
				metric_fetching_channels[db_unique] = make(chan MetricFetchMessage, 100)
				go MetricsFetcher(metric_fetching_channels[db_unique], persist_ch) // close message?
				metric_fetching_channels_lock.Unlock()
				time.Sleep(time.Millisecond * 250) // not to cause a huge load spike when starting the daemon with 20+ monitored DBs
			}

			for metric := range host_config {
				interval := host_config[metric].(float64)

				metric_def_map_lock.RLock()
				_, metric_def_ok := metric_def_map[metric]
				metric_def_map_lock.RUnlock()

				var db_metric string = db_unique + ":" + metric
				_, ch_ok := control_channels[db_metric]

				if metric_def_ok && !ch_ok { // initialize a new per db/per metric control channel
					if interval > 0 {
						host_metric_interval_map[db_metric] = interval
						log.Info("starting gatherer for", db_unique, metric)
						control_channels[db_metric] = make(chan ControlMessage, 1)
						go MetricGathererLoop(db_unique, db_type, metric, host_config, control_channels[db_metric])
					}
				} else if !metric_def_ok && ch_ok {
					// metric definition files were recently removed
					log.Warning("shutting down metric", metric, "for", host["md_unique_name"])
					control_channels[db_metric] <- ControlMessage{Action: "STOP"}
					time.Sleep(time.Second * 1) // enough?
					delete(control_channels, db_metric)
				} else if !metric_def_ok {
					log.Warning(fmt.Sprintf("metric definiton \"%s\" not found for \"%s\"", metric, db_unique))
				} else {
					// check if interval has changed
					if host_metric_interval_map[db_metric] != interval {
						log.Warning("sending interval update for", db_unique, metric)
						control_channels[db_metric] <- ControlMessage{Action: "START", Config: host_config}
						host_metric_interval_map[db_metric] = interval
					}
				}
			}
		}

		// loop over existing channels and stop workers if DB or metric removed from config
		log.Info("checking if any workers need to be shut down...")
	next_chan:
		for db_metric := range control_channels {
			splits := strings.Split(db_metric, ":")
			db := splits[0]
			metric := splits[1]

			for _, host := range monitored_dbs {
				if host["md_unique_name"] == db {
					host_config := jsonTextToMap(host["md_config"].(string))

					for metric_key := range host_config {
						if metric_key == metric && host_config[metric_key].(float64) > 0 {
							continue next_chan
						}
					}
				}
			}

			log.Warning("shutting down gatherer for ", db, ":", metric)
			control_channels[db_metric] <- ControlMessage{Action: "STOP"}
			time.Sleep(time.Second * 1)
			delete(control_channels, db_metric)
			log.Debug("channel deleted for", db_metric)

		}

		log.Debug(fmt.Sprintf("main sleeping %ds...", ACTIVE_SERVERS_REFRESH_TIME))
		time.Sleep(time.Second * time.Duration(ACTIVE_SERVERS_REFRESH_TIME))
	}

}
