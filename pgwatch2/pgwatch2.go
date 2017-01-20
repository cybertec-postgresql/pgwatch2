package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"github.com/influxdata/influxdb/client/v2"
	"github.com/jessevdk/go-flags"
	"github.com/jmoiron/sqlx"
	_ "github.com/lib/pq"
	"github.com/op/go-logging"
	_ "io/ioutil"
	"os"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
	_ "time"
)

type MonitoredDatabase struct {
	DBUniqueName string
	Host         string
	Port         string
	DBName       string
	User         string
	Password     string
	Metrics      map[string]int
}

type ControlMessage struct {
	Action string // START, STOP, PAUSE
	Config map[string]interface{}
}

type MetricFetchMessage struct {
	DBUniqueName string
	MetricName   string
}

type MetricStoreMessage struct {
	DBUniqueName string
	MetricName   string
	Data         [](map[string]interface{})
}

const EPOCH_COLUMN_NAME string = "epoch_ns"      // this column (epoch in nanoseconds) is expected in every metric query
const METRIC_DEFINITION_REFRESH_TIME int64 = 120 // min time before checking for new/changed metric definitions
const ACTIVE_SERVERS_REFRESH_TIME int64 = 60     // min time before checking for new/changed databases under monitoring i.e. main loop time
const STATEMENT_TIMEOUT string = "5s"            // Postgres timeout for metrics fetching queries

var configDb *sqlx.DB
var log = logging.MustGetLogger("main")
var metric_def_map map[string]map[float64]string
var metric_def_map_lock = sync.RWMutex{}
var host_metric_interval_map = make(map[string]float64) // [db1_metric] = 30
var db_pg_version_map = make(map[string]float64)
var db_pg_version_map_lock = sync.RWMutex{}
var InfluxDefaultRetentionPolicyDuration string = "90d" // 90 days of monitoring data will be kept around. adjust if needed
var monitored_db_cache map[string]map[string]interface{}
var monitored_db_cache_lock sync.RWMutex
var metric_fetching_channels = make(map[string](chan MetricFetchMessage)) // [db1unique]=chan
var metric_fetching_channels_lock = sync.RWMutex{}

func GetPostgresDBConnection(host, port, dbname, user, password string) (*sqlx.DB, error) {
	var err error
	var db *sqlx.DB

	log.Debug("Connecting to: ", host, port, dbname, user, password)

	db, err = sqlx.Open("postgres", fmt.Sprintf("host=%s port=%s dbname=%s sslmode=disable user=%s password=%s",
		host, port, dbname, user, password))

	if err != nil {
		log.Error("could not open configDb connection", err)
	}
	return db, err
}

func InitAndTestConfigStoreConnection(host, port, dbname, user, password string) {
	var err error

	configDb, err = GetPostgresDBConnection(host, port, dbname, user, password) // configDb is used by the main thread only
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

func DBExecRead(conn *sqlx.DB, sql string, args ...interface{}) ([](map[string]interface{}), error) {
	ret := make([]map[string]interface{}, 0)

	rows, err := conn.Queryx(sql, args...)
	if err != nil {
		log.Error(err)
		return nil, err
	}
	defer rows.Close()

	for rows.Next() {
		row := make(map[string]interface{})
		err = rows.MapScan(row)
		if err != nil {
			log.Error("failed to MapScan a result row", err)
			return nil, err
		}
		ret = append(ret, row)
	}

	err = rows.Err()
	if err != nil {
		log.Error(err)
	}
	return ret, err
}

func DBExecReadByDbUniqueName(dbUnique string, sql string, args ...interface{}) ([](map[string]interface{}), error) {
	md, err := GetMonitoredDatabaseByUniqueName(dbUnique)
	if err != nil {
		return nil, err
	}
	conn, err := GetPostgresDBConnection(md.Host, md.Port, md.DBName, md.User, md.Password) // TODO pooling
	if err != nil {
		return nil, err
	}
	defer conn.Close()

	DBExecRead(conn, fmt.Sprintf("SET statement_timeout TO '%s'"), STATEMENT_TIMEOUT)

	return DBExecRead(conn, sql, args...)
}

func GetAllActiveHostsFromConfigDB() ([](map[string]interface{}), error) {
	sql := `
		select
		  md_unique_name, md_hostname, md_port, md_dbname, md_user, coalesce(md_password, '') as md_password,
		  coalesce(pc_config, md_config)::text as md_config, now()
		from
		  pgwatch2.monitored_db
	          left join
		  pgwatch2.preset_config on pc_name = md_preset_config_name
		where
		  md_is_enabled
	`
	data, err := DBExecRead(configDb, sql)
	if err != nil {
		log.Error(err)
	} else {
		UpdateMonitoredDBCache(data) // cache used by workers
	}
	return data, err
}

func SendToInflux(dbname, measurement string, data [](map[string]interface{})) error {
	if data == nil {
		return nil
	}
	log.Debug("SendToInflux data[0] of ", len(data), ":", data[0])
	ts_warning_printed := false
retry:
	retries := 1 // 1 retry

	c, err := client.NewHTTPClient(client.HTTPConfig{
		Addr:     opts.InfluxURL,
		Username: opts.InfluxUser,
		Password: opts.InfluxPassword,
	})

	if err != nil {
		log.Error("Error connecting to Influx: ", err)
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
			if !ts_warning_printed {
				log.Warning("No timestamp_ns found, server time will be used. measurement:", measurement)
				ts_warning_printed = true
			}
			epoch_time = time.Now()
		} else {
			epoch_time = time.Unix(0, epoch_ns)
		}

		pt, err := client.NewPoint(measurement, tags, fields, epoch_time)

		if err != nil {
			log.Fatal("NewPoint failed:", err)
		}

		bp.AddPoint(pt)
		rows_batched += 1
	}
	t1 := time.Now()
	err = c.Write(bp)
	t_diff := time.Now().Sub(t1)
	if err == nil {
		log.Info(fmt.Sprintf("wrote %d/%d rows to Influx for [%s:%s] in %dus", rows_batched, len(data),
			dbname, measurement, t_diff.Nanoseconds()/1000))
	}
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
		Host:     monitored_db_cache[name]["md_hostname"].(string),
		Port:     monitored_db_cache[name]["md_port"].(string),
		DBName:   monitored_db_cache[name]["md_dbname"].(string),
		User:     monitored_db_cache[name]["md_user"].(string),
		Password: monitored_db_cache[name]["md_password"].(string),
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

// TODO batching of mutiple datasets
func InfluxPersister(storage_ch <-chan MetricStoreMessage) {
	retry_queue := make([]MetricStoreMessage, 0)

	for {
		select {
		case msg := <-storage_ch:
			log.Debug("got store msg", msg)

			err := SendToInflux(msg.DBUniqueName, msg.MetricName, msg.Data)
			if err != nil {
				// TODO back up to disk when too many failures
				log.Error(err)
				retry_queue = append(retry_queue, msg)
			}
		default:
			for len(retry_queue) > 0 {
				log.Info("processing retry_queue. len(retry_queue) =", len(retry_queue))
				msg := retry_queue[0]

				err := SendToInflux(msg.DBUniqueName, msg.MetricName, msg.Data)
				if err != nil {
					time.Sleep(time.Second * 10)
					break
				}
				retry_queue = retry_queue[1:]
			}

			time.Sleep(time.Millisecond * 100)
		}
	}
}

// TODO cache for 5min
func DBGetPGVersion(dbUnique string) (float64, error) {
	var ver float64
	var ok bool
	sql := `
		select regexp_replace(current_setting('server_version'), E'\\.[0-9]+$', '')::double precision as ver;
	`

	db_pg_version_map_lock.RLock()
	ver, ok = db_pg_version_map[dbUnique]
	db_pg_version_map_lock.RUnlock()

	if !ok {
		log.Info("determining DB version for", dbUnique)
		data, err := DBExecReadByDbUniqueName(dbUnique, sql)
		if err != nil {
			log.Error("DBGetPGVersion failed", err)
			return ver, err
		}
		ver = data[0]["ver"].(float64)
		log.Info(fmt.Sprintf("%s is on version %s", dbUnique, strconv.FormatFloat(ver, 'f', 1, 64)))

		db_pg_version_map_lock.Lock()
		db_pg_version_map[dbUnique] = ver
		db_pg_version_map_lock.Unlock()
	}
	return ver, nil
}

// assumes upwards compatibility for versions
func GetSQLForMetricPGVersion(metric string, pgVer float64) string {
	var keys []float64

	metric_def_map_lock.RLock()
	defer metric_def_map_lock.RUnlock()

	_, ok := metric_def_map[metric]
	if !ok {
		log.Error("metric", metric, "not found")
		return ""
	}

	for k := range metric_def_map[metric] {
		keys = append(keys, k)
	}

	sort.Float64s(keys)

	var best_ver float64
	for _, ver := range keys {
		if pgVer >= ver {
			best_ver = ver
		}
	}

	if best_ver == 0 {
		return ""
	}
	return metric_def_map[metric][best_ver]
}

func MetricsFetcher(fetch_msg <-chan MetricFetchMessage, storage_ch chan<- MetricStoreMessage) {
	for {
		select {
		case msg := <-fetch_msg:
			// DB version lookup
			db_pg_version, err := DBGetPGVersion(msg.DBUniqueName)
			if err != nil {
				log.Error("failed to fetch pg version for ", msg.DBUniqueName, msg.MetricName, err)
				continue
			}

			sql := GetSQLForMetricPGVersion(msg.MetricName, db_pg_version)
			//log.Debug("SQL", sql)

			t1 := time.Now().UnixNano()
			data, err := DBExecReadByDbUniqueName(msg.DBUniqueName, sql)
			t2 := time.Now().UnixNano()
			if err != nil {
				log.Error("failed to fetch metrics for ", msg.DBUniqueName, msg.MetricName, err)
			} else {
				log.Info(fmt.Sprintf("fetched %d rows for [%s:%s] in %dus", len(data), msg.DBUniqueName, msg.MetricName, (t2-t1)/1000))
				if len(data) > 0 {
					storage_ch <- MetricStoreMessage{DBUniqueName: msg.DBUniqueName, MetricName: msg.MetricName, Data: data}
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
func MetricGathererLoop(dbUniqueName string, metricName string, config_map map[string]interface{}, control_ch <-chan ControlMessage) {
	config := config_map
	interval := config[metricName].(float64)
	running := true
	ticker := time.NewTicker(time.Second * time.Duration(interval))

	for {
		if running {
			ForwardQueryMessageToDBUniqueFetcher(MetricFetchMessage{DBUniqueName: dbUniqueName, MetricName: metricName})
		}

		select {
		case msg := <-control_ch:
			log.Info("got control msg", dbUniqueName, metricName, msg)
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
	metric_def_map_new := make(map[string]map[float64]string)
	sql := "select m_name, m_pg_version_from, m_sql from pgwatch2.metric where m_is_active"
	data, err := DBExecRead(configDb, sql)
	if err != nil {
		log.Error(err)
		return
	}
	if len(data) == 0 {
		log.Warning("no metric definitions found from config DB")
		return
	}

	for _, row := range data {
		log.Debug("metric found:", row["m_name"], row["m_pg_version_from"])
		_, ok := metric_def_map_new[row["m_name"].(string)]
		if !ok {
			metric_def_map_new[row["m_name"].(string)] = make(map[float64]string)
		}
		metric_def_map_new[row["m_name"].(string)][row["m_pg_version_from"].(float64)] = row["m_sql"].(string)
	}

	metric_def_map_lock.Lock()
	metric_def_map = metric_def_map_new
	metric_def_map_lock.Unlock()
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

func InitAndTestInfluxConnection(InfluxURL, InfluxDbname string) error {
	log.Info(fmt.Sprintf("Testing Influx connection to URL: %s, DB: %s", InfluxURL, InfluxDbname))

	// Make client
	c, err := client.NewHTTPClient(client.HTTPConfig{
		Addr:     opts.InfluxURL,
		Username: opts.InfluxUser,
		Password: opts.InfluxPassword,
	})

	if err != nil {
		log.Fatal("Gerring Influx client failed", err)
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
			return err
		}
	}

	for _, db_arr := range res[0].Series[0].Values {
		log.Debug("Found db:", db_arr[0])
		if InfluxDbname == db_arr[0] {
			log.Info(fmt.Sprintf("Database '%s' existing", InfluxDbname))
			return nil
		}
	}

	log.Warning(fmt.Sprintf("Database '%s' not found! Creating with 90d retention...", InfluxDbname))
	isql := fmt.Sprintf("CREATE DATABASE %s WITH DURATION %s REPLICATION 1 SHARD DURATION 3d NAME pgwatch_def_ret", InfluxDbname, InfluxDefaultRetentionPolicyDuration)
	res, err = queryDB(c, isql)
	if err != nil {
		log.Fatal(err)
	} else {
		log.Info("Database 'pgwatch2' created")
	}

	return nil
}

var opts struct {
	// Slice of bool will append 'true' each time the option
	// is encountered (can be set multiple times, like -vvv)
	Verbose        []bool `short:"v" long:"verbose" description:"Show verbose debug information"`
	File           string `short:"f" long:"file" description:"Sqlite3 config DB file"`
	Host           string `short:"h" long:"host" description:"PG config DB host" default:"localhost"`
	Port           string `short:"p" long:"port" description:"PG config DB port" default:"5432"`
	Dbname         string `short:"d" long:"dbname" description:"PG config DB dbname" default:"pgwatch2"`
	User           string `short:"u" long:"user" description:"PG config DB host" default:"pgwatch2"`
	Password       string `long:"password" description:"PG config DB password"`
	InfluxURL      string `long:"iurl" description:"Influx address" default:"http://localhost:8086"`
	InfluxDbname   string `long:"idbname" description:"Influx DB name" default:"pgwatch2"`
	InfluxUser     string `long:"iuser" description:"Influx user" default:"root"`
	InfluxPassword string `long:"ipassword" description:"Influx password" default:"root"`
}

func main() {

	_, err := flags.Parse(&opts)
	if flagsErr, ok := err.(*flags.Error); ok && flagsErr.Type == flags.ErrHelp {
		os.Exit(0)
	}

	if len(opts.Verbose) >= 2 {
		logging.SetLevel(logging.DEBUG, "main")
	} else if len(opts.Verbose) == 1 {
		logging.SetLevel(logging.INFO, "main")
	} else {
		logging.SetLevel(logging.WARNING, "main")
	}
	logging.SetFormatter(logging.MustStringFormatter(`%{time:15:04:05.000} %{level:.4s} %{shortfunc}: %{message}`))

	log.Debug("opts", opts)

	if opts.File != "" {
		fmt.Println("Sqlite3 not yet supported")
		return
	} else { // make sure all PG params are there
		if opts.User == "" {
			opts.User = os.Getenv("USER")
		}
		if opts.Host == "" || opts.Port == "" || opts.Dbname == "" || opts.User == "" {
			fmt.Println("Check config DB parameters")
			return
		}
	}

	InitAndTestConfigStoreConnection(opts.Host, opts.Port, opts.Dbname, opts.User, opts.Password)

	err = InitAndTestInfluxConnection(opts.InfluxURL, opts.InfluxDbname)
	if err != nil {
		log.Fatal("Could not initialize InfluxDB", err)
	}
	log.Info("InfluxDB connection OK")

	control_channels := make(map[string](chan ControlMessage)) // [db1+metric1]=chan
	persist_ch := make(chan MetricStoreMessage, 1000)

	log.Info("starting InfluxPersister...")
	go InfluxPersister(persist_ch)

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

			// make sure query channel for every DBUnique exists. means also max 1 concurrent query for 1 DB
			metric_fetching_channels_lock.RLock()
			_, exists := metric_fetching_channels[db_unique]
			metric_fetching_channels_lock.RUnlock()
			if !exists {
				metric_fetching_channels_lock.Lock()
				metric_fetching_channels[db_unique] = make(chan MetricFetchMessage, 100)
				go MetricsFetcher(metric_fetching_channels[db_unique], persist_ch) // close message?
				metric_fetching_channels_lock.Unlock()
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
						log.Info("starting gatherer for ", db_unique, metric)
						control_channels[db_metric] = make(chan ControlMessage, 1)
						go MetricGathererLoop(db_unique, metric, host_config, control_channels[db_metric])
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
