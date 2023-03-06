package main

import (
	"container/list"
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	go_sql "database/sql"
	"encoding/hex"
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
	"syscall"
	"time"

	"github.com/shirou/gopsutil/v3/disk"
	"github.com/shirou/gopsutil/v3/mem"

	"github.com/coreos/go-systemd/daemon"
	client "github.com/influxdata/influxdb1-client/v2"
	"github.com/jessevdk/go-flags"
	"github.com/jmoiron/sqlx"
	"github.com/lib/pq"
	"github.com/marpaia/graphite-golang"
	"github.com/op/go-logging"
	"github.com/shirou/gopsutil/v3/cpu"
	"github.com/shirou/gopsutil/v3/load"
	"github.com/shopspring/decimal"
	"golang.org/x/crypto/pbkdf2"
	"gopkg.in/yaml.v2"
)

var commit = "" // Git hash. Will be set on build time by build_gatherer.sh / goreleaser
var date = ""   // Will be set on build time by build_gatherer.sh / goreleaser

type MonitoredDatabase struct {
	DBUniqueName         string `yaml:"unique_name"`
	DBUniqueNameOrig     string // to preserve belonging to a specific instance for continuous modes where DBUniqueName will be dynamic
	Group                string
	Host                 string
	Port                 string
	DBName               string
	User                 string
	Password             string
	PasswordType         string `yaml:"password_type"`
	LibPQConnStr         string `yaml:"libpq_conn_str"`
	SslMode              string
	SslRootCAPath        string             `yaml:"sslrootcert"`
	SslClientCertPath    string             `yaml:"sslcert"`
	SslClientKeyPath     string             `yaml:"sslkey"`
	Metrics              map[string]float64 `yaml:"custom_metrics"`
	MetricsStandby       map[string]float64 `yaml:"custom_metrics_standby"`
	StmtTimeout          int64              `yaml:"stmt_timeout"`
	DBType               string
	DBNameIncludePattern string            `yaml:"dbname_include_pattern"`
	DBNameExcludePattern string            `yaml:"dbname_exclude_pattern"`
	PresetMetrics        string            `yaml:"preset_metrics"`
	PresetMetricsStandby string            `yaml:"preset_metrics_standby"`
	IsSuperuser          bool              `yaml:"is_superuser"`
	IsEnabled            bool              `yaml:"is_enabled"`
	CustomTags           map[string]string `yaml:"custom_tags"` // ignored on graphite
	HostConfig           HostConfigAttrs   `yaml:"host_config"`
	OnlyIfMaster         bool              `yaml:"only_if_master"`
}

type HostConfigAttrs struct {
	DcsType                string   `yaml:"dcs_type"`
	DcsEndpoints           []string `yaml:"dcs_endpoints"`
	Scope                  string
	Namespace              string
	Username               string
	Password               string
	CAFile                 string                             `yaml:"ca_file"`
	CertFile               string                             `yaml:"cert_file"`
	KeyFile                string                             `yaml:"key_file"`
	LogsGlobPath           string                             `yaml:"logs_glob_path"`   // default $data_directory / $log_directory / *.csvlog
	LogsMatchRegex         string                             `yaml:"logs_match_regex"` // default is for CSVLOG format. needs to capture following named groups: log_time, user_name, database_name and error_severity
	PerMetricDisabledTimes []HostConfigPerMetricDisabledTimes `yaml:"per_metric_disabled_intervals"`
}

type HostConfigPerMetricDisabledTimes struct { // metric gathering override per host / metric / time
	Metrics       []string `yaml:"metrics"`
	DisabledTimes []string `yaml:"disabled_times"`
	DisabledDays  string   `yaml:"disabled_days"`
}

type PatroniClusterMember struct {
	Scope   string
	Name    string
	ConnUrl string `yaml:"conn_url"`
	Role    string
}

type PresetConfig struct {
	Name        string
	Description string
	Metrics     map[string]float64
}

type MetricColumnAttrs struct {
	PrometheusGaugeColumns    []string `yaml:"prometheus_gauge_columns"`
	PrometheusIgnoredColumns  []string `yaml:"prometheus_ignored_columns"` // for cases where we don't want some columns to be exposed in Prom mode
	PrometheusAllGaugeColumns bool     `yaml:"prometheus_all_gauge_columns"`
}

type MetricAttrs struct {
	IsInstanceLevel           bool                 `yaml:"is_instance_level"`
	MetricStorageName         string               `yaml:"metric_storage_name"`
	ExtensionVersionOverrides []ExtensionOverrides `yaml:"extension_version_based_overrides"`
	IsPrivate                 bool                 `yaml:"is_private"`                // used only for extension overrides currently and ignored otherwise
	DisabledDays              string               `yaml:"disabled_days"`             // Cron style, 0 = Sunday. Ranges allowed: 0,2-4
	DisableTimes              []string             `yaml:"disabled_times"`            // "11:00-13:00"
	StatementTimeoutSeconds   int64                `yaml:"statement_timeout_seconds"` // overrides per monitored DB settings
}

type MetricVersionProperties struct {
	Sql                  string
	SqlSU                string
	MasterOnly           bool
	StandbyOnly          bool
	ColumnAttrs          MetricColumnAttrs // Prometheus Metric Type (Counter is default) and ignore list
	MetricAttrs          MetricAttrs
	CallsHelperFunctions bool
}

type ControlMessage struct {
	Action string // START, STOP, PAUSE
	Config map[string]float64
}

type MetricFetchMessage struct {
	DBUniqueName        string
	DBUniqueNameOrig    string
	MetricName          string
	DBType              string
	Interval            time.Duration
	CreatedOn           time.Time
	StmtTimeoutOverride int64
}

type MetricStoreMessage struct {
	DBUniqueName            string
	DBType                  string
	MetricName              string
	CustomTags              map[string]string
	Data                    [](map[string]interface{})
	MetricDefinitionDetails MetricVersionProperties
	RealDbname              string
	SystemIdentifier        string
}

type MetricStoreMessagePostgres struct {
	Time    time.Time
	DBName  string
	Metric  string
	Data    map[string]interface{}
	TagData map[string]interface{}
}

type ChangeDetectionResults struct { // for passing around DDL/index/config change detection results
	Created int
	Altered int
	Dropped int
}

type DBVersionMapEntry struct {
	LastCheckedOn    time.Time
	IsInRecovery     bool
	Version          decimal.Decimal
	VersionStr       string
	RealDbname       string
	SystemIdentifier string
	IsSuperuser      bool // if true and no helpers are installed, use superuser SQL version of metric if available
	Extensions       map[string]decimal.Decimal
	ExecEnv          string
	ApproxDBSizeB    int64
}

type ExistingPartitionInfo struct {
	StartTime time.Time
	EndTime   time.Time
}

type ExtensionOverrides struct {
	TargetMetric              string          `yaml:"target_metric"`
	ExpectedExtensionVersions []ExtensionInfo `yaml:"expected_extension_versions"`
}

type ExtensionInfo struct {
	ExtName       string          `yaml:"ext_name"`
	ExtMinVersion decimal.Decimal `yaml:"ext_min_version"`
}

const EPOCH_COLUMN_NAME string = "epoch_ns" // this column (epoch in nanoseconds) is expected in every metric query
const TAG_PREFIX string = "tag_"
const METRIC_DEFINITION_REFRESH_TIME int64 = 120 // min time before checking for new/changed metric definitions
const GRAPHITE_METRICS_PREFIX string = "pgwatch2"
const PERSIST_QUEUE_MAX_SIZE = 10000 // storage queue max elements. when reaching the limit, older metrics will be dropped.
// actual requirements depend a lot of metric type and nr. of obects in schemas,
// but 100k should be enough for 24h, assuming 5 hosts monitored with "exhaustive" preset config. this would also require ~2 GB RAM per one Influx host
const DATASTORE_INFLUX = "influx"
const DATASTORE_GRAPHITE = "graphite"
const DATASTORE_JSON = "json"
const DATASTORE_POSTGRES = "postgres"
const DATASTORE_PROMETHEUS = "prometheus"
const PRESET_CONFIG_YAML_FILE = "preset-configs.yaml"
const FILE_BASED_METRIC_HELPERS_DIR = "00_helpers"
const PG_CONN_RECYCLE_SECONDS = 1800 // applies for monitored nodes
const APPLICATION_NAME = "pgwatch2"  // will be set on all opened PG connections for informative purposes
const GATHERER_STATUS_START = "START"
const GATHERER_STATUS_STOP = "STOP"
const METRICDB_IDENT = "metricDb"
const CONFIGDB_IDENT = "configDb"
const CONTEXT_PROMETHEUS_SCRAPE = "prometheus-scrape"
const DCS_TYPE_ETCD = "etcd"
const DCS_TYPE_ZOOKEEPER = "zookeeper"
const DCS_TYPE_CONSUL = "consul"
const DBTYPE_PG = "postgres"
const DBTYPE_PG_CONT = "postgres-continuous-discovery"
const DBTYPE_BOUNCER = "pgbouncer"
const DBTYPE_PGPOOL = "pgpool"
const DBTYPE_PATRONI = "patroni"
const DBTYPE_PATRONI_CONT = "patroni-continuous-discovery"
const DBTYPE_PATRONI_NAMESPACE_DISCOVERY = "patroni-namespace-discovery"
const MONITORED_DBS_DATASTORE_SYNC_INTERVAL_SECONDS = 600         // write actively monitored DBs listing to metrics store after so many seconds
const MONITORED_DBS_DATASTORE_SYNC_METRIC_NAME = "configured_dbs" // FYI - for Postgres datastore there's also the admin.all_unique_dbnames table with all recent DB unique names with some metric data
const RECO_PREFIX = "reco_"                                       // special handling for metrics with such prefix, data stored in RECO_METRIC_NAME
const RECO_METRIC_NAME = "recommendations"
const SPECIAL_METRIC_CHANGE_EVENTS = "change_events"
const SPECIAL_METRIC_SERVER_LOG_EVENT_COUNTS = "server_log_event_counts"
const SPECIAL_METRIC_PGBOUNCER = "^pgbouncer_(stats|pools)$"
const SPECIAL_METRIC_PGPOOL_STATS = "pgpool_stats"
const SPECIAL_METRIC_INSTANCE_UP = "instance_up"
const SPECIAL_METRIC_DB_SIZE = "db_size"         // can be transparently switched to db_size_approx on instances with very slow FS access (Azure Single Server)
const SPECIAL_METRIC_TABLE_STATS = "table_stats" // can be transparently switched to table_stats_approx on instances with very slow FS (Azure Single Server)
const METRIC_CPU_LOAD = "cpu_load"
const METRIC_PSUTIL_CPU = "psutil_cpu"
const METRIC_PSUTIL_DISK = "psutil_disk"
const METRIC_PSUTIL_DISK_IO_TOTAL = "psutil_disk_io_total"
const METRIC_PSUTIL_MEM = "psutil_mem"
const DEFAULT_METRICS_DEFINITION_PATH_PKG = "/etc/pgwatch2/metrics" // prebuilt packages / Docker default location
const DEFAULT_METRICS_DEFINITION_PATH_DOCKER = "/pgwatch2/metrics"  // prebuilt packages / Docker default location
const DB_SIZE_CACHING_INTERVAL = 30 * time.Minute
const DB_METRIC_JOIN_STR = "¤¤¤" // just some unlikely string for a DB name to avoid using maps of maps for DB+metric data
const EXEC_ENV_UNKNOWN = "UNKNOWN"
const EXEC_ENV_AZURE_SINGLE = "AZURE_SINGLE"
const EXEC_ENV_AZURE_FLEXIBLE = "AZURE_FLEXIBLE"
const EXEC_ENV_GOOGLE = "GOOGLE"

var dbTypeMap = map[string]bool{DBTYPE_PG: true, DBTYPE_PG_CONT: true, DBTYPE_BOUNCER: true, DBTYPE_PATRONI: true, DBTYPE_PATRONI_CONT: true, DBTYPE_PGPOOL: true, DBTYPE_PATRONI_NAMESPACE_DISCOVERY: true}
var dbTypes = []string{DBTYPE_PG, DBTYPE_PG_CONT, DBTYPE_BOUNCER, DBTYPE_PATRONI, DBTYPE_PATRONI_CONT, DBTYPE_PATRONI_NAMESPACE_DISCOVERY} // used for informational purposes
var specialMetrics = map[string]bool{RECO_METRIC_NAME: true, SPECIAL_METRIC_CHANGE_EVENTS: true, SPECIAL_METRIC_SERVER_LOG_EVENT_COUNTS: true}
var directlyFetchableOSMetrics = map[string]bool{METRIC_PSUTIL_CPU: true, METRIC_PSUTIL_DISK: true, METRIC_PSUTIL_DISK_IO_TOTAL: true, METRIC_PSUTIL_MEM: true, METRIC_CPU_LOAD: true}
var configDb *sqlx.DB
var metricDb *sqlx.DB
var graphiteConnection *graphite.Graphite
var graphite_host string
var graphite_port int
var log = logging.MustGetLogger("main")
var metric_def_map map[string]map[decimal.Decimal]MetricVersionProperties
var metric_def_map_lock = sync.RWMutex{}
var host_metric_interval_map = make(map[string]float64) // [db1_metric] = 30
var db_pg_version_map = make(map[string]DBVersionMapEntry)
var db_pg_version_map_lock = sync.RWMutex{}
var db_get_pg_version_map_lock = make(map[string]sync.RWMutex) // synchronize initial PG version detection to 1 instance for each defined host
var monitored_db_cache map[string]MonitoredDatabase
var monitored_db_cache_lock sync.RWMutex
var monitored_db_conn_cache map[string]*sqlx.DB = make(map[string]*sqlx.DB)
var monitored_db_conn_cache_lock = sync.RWMutex{}
var last_sql_fetch_error sync.Map
var influx_host_count = 1
var InfluxConnectStrings [2]string // Max. 2 Influx metrics stores currently supported
var InfluxSkipSSLCertVerify, InfluxSkipSSLCertVerify2 bool

// secondary Influx meant for HA or Grafana load balancing for 100+ instances with lots of alerts
var fileBasedMetrics = false
var adHocMode = false
var preset_metric_def_map map[string]map[string]float64 // read from metrics folder in "file mode"
// / internal statistics calculation
var lastSuccessfulDatastoreWriteTimeEpoch int64
var datastoreWriteFailuresCounter uint64
var datastoreWriteSuccessCounter uint64
var totalMetricFetchFailuresCounter uint64
var datastoreTotalWriteTimeMicroseconds uint64
var totalMetricsFetchedCounter uint64
var totalMetricsReusedFromCacheCounter uint64
var totalMetricsDroppedCounter uint64
var totalDatasetsFetchedCounter uint64
var metricPointsPerMinuteLast5MinAvg int64 = -1 // -1 means the summarization ticker has not yet run
var gathererStartTime time.Time = time.Now()
var useConnPooling bool
var partitionMapMetric = make(map[string]ExistingPartitionInfo)                  // metric = min/max bounds
var partitionMapMetricDbname = make(map[string]map[string]ExistingPartitionInfo) // metric[dbname = min/max bounds]
var testDataGenerationModeWG sync.WaitGroup
var PGDummyMetricTables = make(map[string]time.Time)
var PGDummyMetricTablesLock = sync.RWMutex{}
var PGSchemaType string
var failedInitialConnectHosts = make(map[string]bool) // hosts that couldn't be connected to even once
var addRealDbname bool
var addSystemIdentifier bool
var noHelperFunctions bool
var forceRecreatePGMetricPartitions = false // to signal override PG metrics storage cache
var lastMonitoredDBsUpdate time.Time
var instanceMetricCache = make(map[string]([]map[string]interface{})) // [dbUnique+metric]lastly_fetched_data
var instanceMetricCacheLock = sync.RWMutex{}
var instanceMetricCacheTimestamp = make(map[string]time.Time) // [dbUnique+metric]last_fetch_time
var instanceMetricCacheTimestampLock = sync.RWMutex{}
var MinExtensionInfoAvailable, _ = decimal.NewFromString("9.1")
var regexIsAlpha = regexp.MustCompile("^[a-zA-Z]+$")
var rBouncerAndPgpoolVerMatch = regexp.MustCompile(`\d+\.+\d+`) // extract $major.minor from "4.1.2 (karasukiboshi)" or "PgBouncer 1.12.0"
var regexIsPgbouncerMetrics = regexp.MustCompile(SPECIAL_METRIC_PGBOUNCER)
var tryDirectOSStats bool
var unreachableDBsLock sync.RWMutex
var unreachableDB = make(map[string]time.Time)
var pgBouncerNumericCountersStartVersion decimal.Decimal // pgBouncer changed internal counters data type in v1.12
// "cache" of last CPU utilization stats for GetGoPsutilCPU to get more exact results and not having to sleep
var prevCPULoadTimeStatsLock sync.RWMutex
var prevCPULoadTimeStats cpu.TimesStat
var prevCPULoadTimestamp time.Time

// Async Prom cache
var promAsyncMetricCache = make(map[string]map[string][]MetricStoreMessage) // [dbUnique][metric]lastly_fetched_data
var promAsyncMetricCacheLock = sync.RWMutex{}
var promAsyncMode = false
var lastDBSizeMB = make(map[string]int64)
var lastDBSizeFetchTime = make(map[string]time.Time) // cached for DB_SIZE_CACHING_INTERVAL
var lastDBSizeCheckLock sync.RWMutex
var mainLoopInitialized int32 // 0/1

var prevLoopMonitoredDBs []MonitoredDatabase // to be able to detect DBs removed from config
var undersizedDBs = make(map[string]bool)    // DBs below the --min-db-size-mb limit, if set
var undersizedDBsLock = sync.RWMutex{}
var recoveryIgnoredDBs = make(map[string]bool) // DBs in recovery state and OnlyIfMaster specified in config
var recoveryIgnoredDBsLock = sync.RWMutex{}
var regexSQLHelperFunctionCalled = regexp.MustCompile(`(?si)^\s*(select|with).*\s+get_\w+\(\)[\s,$]+`) // SQL helpers expected to follow get_smth() naming
var metricNameRemaps = make(map[string]string)
var metricNameRemapLock = sync.RWMutex{}

func IsPostgresDBType(dbType string) bool {
	if dbType == DBTYPE_BOUNCER || dbType == DBTYPE_PGPOOL {
		return false
	}
	return true
}

func GetPostgresDBConnection(libPqConnString, host, port, dbname, user, password, sslmode, sslrootcert, sslcert, sslkey string) (*sqlx.DB, error) {
	var connStr string

	//log.Debug("Connecting to: ", host, port, dbname, user, password)
	if len(libPqConnString) > 0 {
		connStr = libPqConnString
		if !strings.Contains(strings.ToLower(connStr), "sslmode") {
			if strings.Contains(connStr, "postgresql://") || strings.Contains(connStr, "postgres://") { // JDBC style
				if strings.Contains(connStr, "?") { // has some extra params already
					connStr += "&sslmode=disable" // defaulting to "disable" as Go driver doesn't support "prefer"
				} else {
					connStr += "?sslmode=disable"
				}
			} else { // LibPQ style
				connStr += " sslmode=disable"
			}
		}
		if !strings.Contains(strings.ToLower(connStr), "connect_timeout") {
			if strings.Contains(connStr, "postgresql://") || strings.Contains(connStr, "postgres://") { // JDBC style
				if strings.Contains(connStr, "?") { // has some extra params already
					connStr += "&connect_timeout=5" // 5 seconds
				} else {
					connStr += "?connect_timeout=5"
				}
			} else { // LibPQ style
				connStr += " connect_timeout=5"
			}
		}
	} else {
		connStr = fmt.Sprintf("host=%s port=%s dbname='%s' sslmode=%s user=%s application_name=%s sslrootcert='%s' sslcert='%s' sslkey='%s' connect_timeout=5",
			host, port, dbname, sslmode, user, APPLICATION_NAME, sslrootcert, sslcert, sslkey)
		if password != "" { // having empty string as password effectively disables .pgpass so include only if password given
			connStr += fmt.Sprintf(" password='%s'", password)
		}
	}

	return sqlx.Open("postgres", connStr)
}

func StringToBoolOrFail(boolAsString, inputParamName string) bool {
	conversionMap := map[string]bool{
		"true": true, "t": true, "on": true, "y": true, "yes": true, "require": true, "1": true,
		"false": false, "f": false, "off": false, "n": false, "no": false, "disable": false, "0": false,
	}
	val, ok := conversionMap[strings.TrimSpace(strings.ToLower(boolAsString))]
	if !ok {
		if inputParamName != "" {
			log.Fatalf("invalid input for boolean string parameter \"%s\": \"%s\". can be of: 1, t, T, TRUE, true, True, 0, f, F, FALSE, false, False", inputParamName, boolAsString)
		} else {
			log.Fatalf("invalid input for boolean string: %s. can be of: 1, t, T, TRUE, true, True, 0, f, F, FALSE, false, False", boolAsString)
		}

	}
	return val
}

func InitAndTestConfigStoreConnection(host, port, dbname, user, password, requireSSL string, failOnErr bool) error {
	var err error
	SSLMode := "disable"
	var retries = 3 // ~15s

	if StringToBoolOrFail(requireSSL, "--pg-require-ssl") {
		SSLMode = "require"
	}

	for i := 0; i <= retries; i++ {
		// configDb is used by the main thread only. no verify-ca/verify-full support currently
		configDb, err = GetPostgresDBConnection("", host, port, dbname, user, password, SSLMode, "", "", "")
		if err != nil {
			if i < retries {
				log.Errorf("could not open metricDb connection. retrying in 5s. %d retries left. err: %v", retries-i, err)
				time.Sleep(time.Second * 5)
				continue
			}
			if failOnErr {
				log.Fatal("could not open configDb connection! exit.")
			} else {
				log.Error("could not open configDb connection!")
				return err
			}
		}

		err = configDb.Ping()

		if err != nil {
			if i < retries {
				log.Errorf("could not ping configDb! retrying in 5s. %d retries left. err: %v", retries-i, err)
				time.Sleep(time.Second * 5)
				continue
			}
			if failOnErr {
				log.Fatal("could not ping configDb! exit.", err)
			} else {
				log.Error("could not ping configDb!", err)
				return err
			}
		} else {
			log.Info("connect to configDb OK!")
			break
		}
	}
	configDb.SetMaxIdleConns(1)
	configDb.SetMaxOpenConns(2)
	configDb.SetConnMaxLifetime(time.Second * time.Duration(PG_CONN_RECYCLE_SECONDS))
	return nil
}

func InitAndTestMetricStoreConnection(connStr string, failOnErr bool) error {
	var err error
	var retries = 3 // ~15s

	for i := 0; i <= retries; i++ {

		metricDb, err = GetPostgresDBConnection(connStr, "", "", "", "", "", "", "", "", "")
		if err != nil {
			if i < retries {
				log.Errorf("could not open metricDb connection. retrying in 5s. %d retries left. err: %v", retries-i, err)
				time.Sleep(time.Second * 5)
				continue
			}
			if failOnErr {
				log.Fatal("could not open metricDb connection! exit. err:", err)
			} else {
				log.Error("could not open metricDb connection:", err)
				return err
			}
		}

		err = metricDb.Ping()

		if err != nil {
			if i < retries {
				log.Errorf("could not ping metricDb! retrying in 5s. %d retries left. err: %v", retries-i, err)
				time.Sleep(time.Second * 5)
				continue
			}
			if failOnErr {
				log.Fatal("could not ping metricDb! exit.", err)
			} else {
				return err
			}
		} else {
			log.Info("connect to metricDb OK!")
			break
		}
	}
	metricDb.SetMaxIdleConns(2)
	metricDb.SetMaxOpenConns(2)
	metricDb.SetConnMaxLifetime(time.Second * 172800) // 2d
	return nil
}

// every DB under monitoring should have exactly 1 sql.DB connection assigned, that will internally limit parallel access
func InitSqlConnPoolForMonitoredDBIfNil(md MonitoredDatabase) error {
	monitored_db_conn_cache_lock.Lock()
	defer monitored_db_conn_cache_lock.Unlock()

	conn, ok := monitored_db_conn_cache[md.DBUniqueName]
	if ok && conn != nil {
		return nil
	}

	if md.DBType == DBTYPE_BOUNCER {
		md.DBName = "pgbouncer"
	}

	conn, err := GetPostgresDBConnection(md.LibPQConnStr, md.Host, md.Port, md.DBName, md.User, md.Password,
		md.SslMode, md.SslRootCAPath, md.SslClientCertPath, md.SslClientKeyPath)
	if err != nil {
		return err
	}

	if useConnPooling {
		conn.SetMaxIdleConns(opts.MaxParallelConnectionsPerDb)
	} else {
		conn.SetMaxIdleConns(0)
	}
	conn.SetMaxOpenConns(opts.MaxParallelConnectionsPerDb)
	// recycling periodically makes sense as long sessions might bloat memory or maybe conn info (password) was changed
	conn.SetConnMaxLifetime(time.Second * time.Duration(PG_CONN_RECYCLE_SECONDS))

	monitored_db_conn_cache[md.DBUniqueName] = conn
	log.Debugf("[%s] Connection pool initialized with max %d parallel connections. Conn pooling: %v", md.DBUniqueName, opts.MaxParallelConnectionsPerDb, useConnPooling)

	return nil
}

func CloseOrLimitSqlConnPoolForMonitoredDBIfAny(dbUnique string) {
	monitored_db_conn_cache_lock.Lock()
	defer monitored_db_conn_cache_lock.Unlock()

	conn, ok := monitored_db_conn_cache[dbUnique]
	if !ok || conn == nil {
		return
	}

	if IsDBUndersized(dbUnique) || IsDBIgnoredBasedOnRecoveryState(dbUnique) {

		if useConnPooling {
			s := conn.Stats()
			if s.MaxOpenConnections > 1 {
				log.Debugf("[%s] Limiting SQL connection pool to max 1 connection due to dormant state ...", dbUnique)
				conn.SetMaxIdleConns(1)
				conn.SetMaxOpenConns(1)
			}
		}

	} else { // removed from config
		log.Debugf("[%s] Closing SQL connection pool ...", dbUnique)
		err := conn.Close()
		if err != nil {
			log.Error("[%s] Failed to close connection pool to %s nicely. Err: %v", dbUnique, err)
		}
		delete(monitored_db_conn_cache, dbUnique)
	}
}

func RestoreSqlConnPoolLimitsForPreviouslyDormantDB(dbUnique string) {
	if !useConnPooling {
		return
	}
	monitored_db_conn_cache_lock.Lock()
	defer monitored_db_conn_cache_lock.Unlock()

	conn, ok := monitored_db_conn_cache[dbUnique]
	if !ok || conn == nil {
		log.Error("DB conn to re-instate pool limits not found, should not happen")
		return
	}

	log.Debugf("[%s] Re-instating SQL connection pool max connections ...", dbUnique)

	conn.SetMaxIdleConns(opts.MaxParallelConnectionsPerDb)
	conn.SetMaxOpenConns(opts.MaxParallelConnectionsPerDb)

}

func InitPGVersionInfoFetchingLockIfNil(md MonitoredDatabase) {
	db_pg_version_map_lock.Lock()
	if _, ok := db_get_pg_version_map_lock[md.DBUniqueName]; !ok {
		db_get_pg_version_map_lock[md.DBUniqueName] = sync.RWMutex{}
	}
	db_pg_version_map_lock.Unlock()
}

func DBExecRead(conn *sqlx.DB, host_ident, sql string, args ...interface{}) ([](map[string]interface{}), error) {
	ret := make([]map[string]interface{}, 0)
	var rows *sqlx.Rows
	var err error

	if conn == nil {
		return nil, errors.New("nil connection")
	}

	rows, err = conn.Queryx(sql, args...)

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

func DBExecInExplicitTX(conn *sqlx.DB, host_ident, sql string, args ...interface{}) ([](map[string]interface{}), error) {
	ret := make([]map[string]interface{}, 0)
	var rows *sqlx.Rows
	var err error

	if conn == nil {
		return nil, errors.New("nil connection")
	}

	ctx := context.Background()
	txOpts := go_sql.TxOptions{ReadOnly: true}

	tx, err := conn.BeginTxx(ctx, &txOpts)
	if err != nil {
		return ret, err
	}
	defer tx.Commit()

	rows, err = tx.Queryx(sql, args...)

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

func DBExecReadByDbUniqueName(dbUnique, metricName string, stmtTimeoutOverride int64, sql string, args ...interface{}) ([](map[string]interface{}), error, time.Duration) {
	var conn *sqlx.DB
	var md MonitoredDatabase
	var data [](map[string]interface{})
	var err error
	var duration time.Duration
	var exists bool
	var sqlStmtTimeout string
	var sqlLockTimeout = "SET LOCAL lock_timeout TO '100ms';"

	if strings.TrimSpace(sql) == "" {
		return nil, errors.New("empty SQL"), duration
	}

	md, err = GetMonitoredDatabaseByUniqueName(dbUnique)
	if err != nil {
		return nil, err, duration
	}

	monitored_db_conn_cache_lock.RLock()
	// sqlx.DB itself is parallel safe
	conn, exists = monitored_db_conn_cache[dbUnique]
	monitored_db_conn_cache_lock.RUnlock()
	if !exists || conn == nil {
		log.Errorf("SQL connection for dbUnique %s not found or nil", dbUnique) // Should always be initialized in the main loop DB discovery code ...
		return nil, errors.New("SQL connection not found or nil"), duration
	}

	if !adHocMode && IsPostgresDBType(md.DBType) {
		stmtTimeout := md.StmtTimeout
		if stmtTimeoutOverride > 0 {
			stmtTimeout = stmtTimeoutOverride
		}
		if stmtTimeout > 0 { // 0 = don't change, use DB level settings
			if useConnPooling {
				sqlStmtTimeout = fmt.Sprintf("SET LOCAL statement_timeout TO '%ds';", stmtTimeout)
			} else {
				sqlStmtTimeout = fmt.Sprintf("SET statement_timeout TO '%ds';", stmtTimeout)
			}

		}
		if err != nil {
			atomic.AddUint64(&totalMetricFetchFailuresCounter, 1)
			return nil, err, duration
		}
	}

	if IsPostgresDBType(md.DBType) {
		if !useConnPooling {
			sqlLockTimeout = "SET lock_timeout TO '100ms';"
		}
	} else {
		sqlLockTimeout = ""
	}

	sqlToExec := sqlLockTimeout + sqlStmtTimeout + sql // bundle timeouts with actual SQL to reduce round-trip times
	//log.Debugf("Executing SQL: %s", sqlToExec)
	t1 := time.Now()
	if IsPostgresDBType(md.DBType) {
		if useConnPooling {
			data, err = DBExecInExplicitTX(conn, dbUnique, sqlToExec, args...)
		} else {
			data, err = DBExecRead(conn, dbUnique, sqlToExec, args...)
		}
	} else {
		for _, sql := range strings.Split(sqlToExec, ";") {
			sql = strings.TrimSpace(sql)
			if len(sql) > 0 {
				data, err = DBExecRead(conn, dbUnique, sql, args...)
			}
		}
	}
	t2 := time.Now()
	if err != nil {
		atomic.AddUint64(&totalMetricFetchFailuresCounter, 1)
	}

	return data, err, t2.Sub(t1)
}

func GetAllActiveHostsFromConfigDB() ([](map[string]interface{}), error) {
	sql_latest := `
		select /* pgwatch2_generated */
		  md_unique_name, md_group, md_dbtype, md_hostname, md_port, md_dbname, md_user, coalesce(md_password, '') as md_password,
		  coalesce(p.pc_config, md_config)::text as md_config, coalesce(s.pc_config, md_config_standby, '{}'::jsonb)::text as md_config_standby,
		  md_statement_timeout_seconds, md_sslmode, md_is_superuser,
		  coalesce(md_include_pattern, '') as md_include_pattern, coalesce(md_exclude_pattern, '') as md_exclude_pattern,
		  coalesce(md_custom_tags::text, '{}') as md_custom_tags, md_root_ca_path, md_client_cert_path, md_client_key_path,
		  md_password_type, coalesce(md_host_config, '{}')::text as md_host_config, md_only_if_master
		from
		  pgwatch2.monitored_db
	          left join
		  pgwatch2.preset_config p on p.pc_name = md_preset_config_name /* primary preset if any */
	          left join
		  pgwatch2.preset_config s on s.pc_name = md_preset_config_name_standby /* standby preset if any */
		where
		  md_is_enabled
	`
	sql_prev := `
		select /* pgwatch2_generated */
		  md_unique_name, md_group, md_dbtype, md_hostname, md_port, md_dbname, md_user, coalesce(md_password, '') as md_password,
		  coalesce(pc_config, md_config)::text as md_config, md_statement_timeout_seconds, md_sslmode, md_is_superuser,
		  coalesce(md_include_pattern, '') as md_include_pattern, coalesce(md_exclude_pattern, '') as md_exclude_pattern,
		  coalesce(md_custom_tags::text, '{}') as md_custom_tags, md_root_ca_path, md_client_cert_path, md_client_key_path,
		  md_password_type, coalesce(md_host_config, '{}')::text as md_host_config, md_only_if_master
		from
		  pgwatch2.monitored_db
	          left join
		  pgwatch2.preset_config on pc_name = md_preset_config_name
		where
		  md_is_enabled
	`
	data, err := DBExecRead(configDb, CONFIGDB_IDENT, sql_latest)
	if err != nil {
		err1 := err
		log.Debugf("Failed to query the monitored DB-s config with latest SQL: %v ", err1)
		data, err = DBExecRead(configDb, CONFIGDB_IDENT, sql_prev)
		if err == nil {
			log.Warning("Fetching monitored DB-s config succeeded with SQL from previous schema version - gatherer update required!")
		} else {
			log.Errorf("Failed to query the monitored DB-s config: %v", err1) // show the original error
		}
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

		metricConfig, err := jsonTextToMap(row["md_config"].(string))
		if err != nil {
			log.Warningf("Cannot parse metrics JSON config for \"%s\": %v", row["md_unique_name"].(string), err)
			continue
		}
		metricConfigStandby := make(map[string]float64)
		if configStandby, ok := row["md_config_standby"]; ok {
			metricConfigStandby, err = jsonTextToMap(configStandby.(string))
			if err != nil {
				log.Warningf("Cannot parse standby metrics JSON config for \"%s\". Ignoring standby config: %v", row["md_unique_name"].(string), err)
			}
		}
		customTags, err := jsonTextToStringMap(row["md_custom_tags"].(string))
		if err != nil {
			log.Warningf("Cannot parse custom tags JSON for \"%s\". Ignoring custom tags. Error: %v", row["md_unique_name"].(string), err)
			customTags = nil
		}
		hostConfigAttrs := HostConfigAttrs{}
		err = yaml.Unmarshal([]byte(row["md_host_config"].(string)), &hostConfigAttrs)
		if err != nil {
			log.Warningf("Cannot parse host config JSON for \"%s\". Ignoring host config. Error: %v", row["md_unique_name"].(string), err)
		}

		md := MonitoredDatabase{
			DBUniqueName:         row["md_unique_name"].(string),
			DBUniqueNameOrig:     row["md_unique_name"].(string),
			Host:                 row["md_hostname"].(string),
			Port:                 row["md_port"].(string),
			DBName:               row["md_dbname"].(string),
			User:                 row["md_user"].(string),
			IsSuperuser:          row["md_is_superuser"].(bool),
			Password:             row["md_password"].(string),
			PasswordType:         row["md_password_type"].(string),
			SslMode:              row["md_sslmode"].(string),
			SslRootCAPath:        row["md_root_ca_path"].(string),
			SslClientCertPath:    row["md_client_cert_path"].(string),
			SslClientKeyPath:     row["md_client_key_path"].(string),
			StmtTimeout:          row["md_statement_timeout_seconds"].(int64),
			Metrics:              metricConfig,
			MetricsStandby:       metricConfigStandby,
			DBType:               row["md_dbtype"].(string),
			DBNameIncludePattern: row["md_include_pattern"].(string),
			DBNameExcludePattern: row["md_exclude_pattern"].(string),
			Group:                row["md_group"].(string),
			HostConfig:           hostConfigAttrs,
			OnlyIfMaster:         row["md_only_if_master"].(bool),
			CustomTags:           customTags}

		if _, ok := dbTypeMap[md.DBType]; !ok {
			log.Warningf("Ignoring host \"%s\" - unknown dbtype: %s. Expected one of: %+v", md.DBUniqueName, md.DBType, dbTypes)
			continue
		}

		if md.PasswordType == "aes-gcm-256" && opts.AesGcmKeyphrase != "" {
			md.Password = decrypt(md.DBUniqueName, opts.AesGcmKeyphrase, md.Password)
		}

		if md.DBType == DBTYPE_PG_CONT {
			resolved, err := ResolveDatabasesFromConfigEntry(md)
			if err != nil {
				log.Errorf("Failed to resolve DBs for \"%s\": %s", md.DBUniqueName, err)
				if md.PasswordType == "aes-gcm-256" && opts.AesGcmKeyphrase == "" {
					log.Errorf("No decryption key set. Use the --aes-gcm-keyphrase or --aes-gcm-keyphrase params to set")
				}
				continue
			}
			temp_arr := make([]string, 0)
			for _, rdb := range resolved {
				monitoredDBs = append(monitoredDBs, rdb)
				temp_arr = append(temp_arr, rdb.DBName)
			}
			log.Debugf("Resolved %d DBs with prefix \"%s\": [%s]", len(resolved), md.DBUniqueName, strings.Join(temp_arr, ", "))
		} else if md.DBType == DBTYPE_PATRONI || md.DBType == DBTYPE_PATRONI_CONT || md.DBType == DBTYPE_PATRONI_NAMESPACE_DISCOVERY {
			resolved, err := ResolveDatabasesFromPatroni(md)
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
	if len(storeMessages) == 0 {
		return nil
	}
	skipSSLCertVerify := InfluxSkipSSLCertVerify // conn_id == "0"
	if conn_id == "1" {
		skipSSLCertVerify = InfluxSkipSSLCertVerify2
	}
	ts_warning_printed := false
	retries := 1 // 1 retry
retry:

	c, err := client.NewHTTPClient(client.HTTPConfig{
		Addr:               connect_str,
		Username:           opts.InfluxUser,
		Password:           opts.InfluxPassword,
		InsecureSkipVerify: skipSSLCertVerify,
	})

	if err != nil {
		log.Error("Error connecting to Influx", conn_id, ": ", err)
		if retries > 0 {
			retries--
			time.Sleep(time.Millisecond * 200)
			goto retry
		}
		atomic.AddUint64(&datastoreWriteFailuresCounter, 1)
		return err
	}
	defer c.Close()

	bp, err := client.NewBatchPoints(client.BatchPointsConfig{Database: opts.InfluxDbname})

	if err != nil {
		atomic.AddUint64(&datastoreWriteFailuresCounter, 1)
		return err
	}
	rows_batched := 0
	total_rows := 0

	for _, msg := range storeMessages {
		if msg.Data == nil || len(msg.Data) == 0 {
			continue
		}
		log.Debugf("SendToInflux %s data[0] of %d [%s:%s]: %v", conn_id, len(msg.Data), msg.DBUniqueName, msg.MetricName, msg.Data[0])

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
				} else if strings.HasPrefix(k, TAG_PREFIX) {
					tag := k[4:]
					tags[tag] = fmt.Sprintf("%v", v)
				} else {
					fields[k] = v
				}
			}

			if epoch_ns == 0 {
				if !ts_warning_printed && !regexIsPgbouncerMetrics.MatchString(msg.MetricName) {
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
	t_diff := time.Since(t1)
	if err == nil {
		if len(storeMessages) == 1 {
			log.Infof("wrote %d/%d rows to InfluxDB %s for [%s:%s] in %.1f ms", rows_batched, total_rows,
				conn_id, storeMessages[0].DBUniqueName, storeMessages[0].MetricName, float64(t_diff.Nanoseconds())/1000000.0)
		} else {
			log.Infof("wrote %d/%d rows from %d metric sets to InfluxDB %s in %.1f ms", rows_batched, total_rows,
				len(storeMessages), conn_id, float64(t_diff.Nanoseconds())/1000000.0)
		}
		atomic.StoreInt64(&lastSuccessfulDatastoreWriteTimeEpoch, t1.Unix())
		atomic.AddUint64(&datastoreTotalWriteTimeMicroseconds, uint64(t_diff.Microseconds()))
		atomic.AddUint64(&datastoreWriteSuccessCounter, 1)
	} else {
		atomic.AddUint64(&datastoreWriteFailuresCounter, 1)
	}
	return err
}

func SendToPostgres(storeMessages []MetricStoreMessage) error {
	if len(storeMessages) == 0 {
		return nil
	}
	ts_warning_printed := false
	metricsToStorePerMetric := make(map[string][]MetricStoreMessagePostgres)
	rows_batched := 0
	total_rows := 0
	pg_part_bounds := make(map[string]ExistingPartitionInfo)                   // metric=min/max
	pg_part_bounds_dbname := make(map[string]map[string]ExistingPartitionInfo) // metric=[dbname=min/max]
	var err error

	if PGSchemaType == "custom" {
		metricsToStorePerMetric["metrics"] = make([]MetricStoreMessagePostgres, 0) // everything inserted into "metrics".
		// TODO  warn about collision if someone really names some new metric "metrics"
	}

	for _, msg := range storeMessages {
		if msg.Data == nil || len(msg.Data) == 0 {
			continue
		}
		log.Debug("SendToPG data[0] of ", len(msg.Data), ":", msg.Data[0])

		for _, dr := range msg.Data {
			var epoch_time time.Time
			var epoch_ns int64

			tags := make(map[string]interface{})
			fields := make(map[string]interface{})

			total_rows += 1

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
				} else if strings.HasPrefix(k, TAG_PREFIX) {
					tag := k[4:]
					tags[tag] = fmt.Sprintf("%v", v)
				} else {
					fields[k] = v
				}
			}

			if epoch_ns == 0 {
				if !ts_warning_printed && !regexIsPgbouncerMetrics.MatchString(msg.MetricName) {
					log.Warning("No timestamp_ns found, server time will be used. measurement:", msg.MetricName)
					ts_warning_printed = true
				}
				epoch_time = time.Now()
			} else {
				epoch_time = time.Unix(0, epoch_ns)
			}

			var metricsArr []MetricStoreMessagePostgres
			var ok bool
			var metricNameTemp string

			if PGSchemaType == "custom" {
				metricNameTemp = "metrics"
			} else {
				metricNameTemp = msg.MetricName
			}

			metricsArr, ok = metricsToStorePerMetric[metricNameTemp]
			if !ok {
				metricsToStorePerMetric[metricNameTemp] = make([]MetricStoreMessagePostgres, 0)
			}
			metricsArr = append(metricsArr, MetricStoreMessagePostgres{Time: epoch_time, DBName: msg.DBUniqueName,
				Metric: msg.MetricName, Data: fields, TagData: tags})
			metricsToStorePerMetric[metricNameTemp] = metricsArr

			rows_batched += 1

			if PGSchemaType == "metric" || PGSchemaType == "metric-time" || PGSchemaType == "timescale" {
				// set min/max timestamps to check/create partitions
				bounds, ok := pg_part_bounds[msg.MetricName]
				if !ok || (ok && epoch_time.Before(bounds.StartTime)) {
					bounds.StartTime = epoch_time
					pg_part_bounds[msg.MetricName] = bounds
				}
				if !ok || (ok && epoch_time.After(bounds.EndTime)) {
					bounds.EndTime = epoch_time
					pg_part_bounds[msg.MetricName] = bounds
				}
			} else if PGSchemaType == "metric-dbname-time" {
				_, ok := pg_part_bounds_dbname[msg.MetricName]
				if !ok {
					pg_part_bounds_dbname[msg.MetricName] = make(map[string]ExistingPartitionInfo)
				}
				bounds, ok := pg_part_bounds_dbname[msg.MetricName][msg.DBUniqueName]
				if !ok || (ok && epoch_time.Before(bounds.StartTime)) {
					bounds.StartTime = epoch_time
					pg_part_bounds_dbname[msg.MetricName][msg.DBUniqueName] = bounds
				}
				if !ok || (ok && epoch_time.After(bounds.EndTime)) {
					bounds.EndTime = epoch_time
					pg_part_bounds_dbname[msg.MetricName][msg.DBUniqueName] = bounds
				}
			}
		}
	}

	if PGSchemaType == "metric" {
		err = EnsureMetric(pg_part_bounds, forceRecreatePGMetricPartitions)
	} else if PGSchemaType == "metric-time" {
		err = EnsureMetricTime(pg_part_bounds, forceRecreatePGMetricPartitions, false)
	} else if PGSchemaType == "metric-dbname-time" {
		err = EnsureMetricDbnameTime(pg_part_bounds_dbname, forceRecreatePGMetricPartitions)
	} else if PGSchemaType == "timescale" {
		err = EnsureMetricTimescale(pg_part_bounds, forceRecreatePGMetricPartitions)
	} else {
		log.Fatal("should never happen...")
	}
	if forceRecreatePGMetricPartitions {
		forceRecreatePGMetricPartitions = false
	}
	if err != nil {
		atomic.AddUint64(&datastoreWriteFailuresCounter, 1)
		return err
	}

	// send data to PG, with a separate COPY for all metrics
	log.Debugf("COPY-ing %d metrics to Postgres metricsDB...", rows_batched)
	t1 := time.Now()

	txn, err := metricDb.Begin()
	if err != nil {
		log.Error("Could not start Postgres metricsDB transaction:", err)
		atomic.AddUint64(&datastoreWriteFailuresCounter, 1)
		return err
	}
	defer func() {
		if err == nil {
			tx_err := txn.Commit()
			if tx_err != nil {
				log.Debug("COPY Commit to Postgres failed:", tx_err)
			}
		} else {
			tx_err := txn.Rollback()
			if tx_err != nil {
				log.Debug("COPY Rollback to Postgres failed:", tx_err)
			}
		}
	}()

	for metricName, metrics := range metricsToStorePerMetric {
		var stmt *go_sql.Stmt

		if PGSchemaType == "custom" {
			stmt, err = txn.Prepare(pq.CopyIn("metrics", "time", "dbname", "metric", "data", "tag_data"))
			if err != nil {
				log.Error("Could not prepare COPY to 'metrics' table:", err)
				atomic.AddUint64(&datastoreWriteFailuresCounter, 1)
				return err
			}
		} else {
			log.Debugf("COPY-ing %d rows into '%s'...", len(metrics), metricName)
			stmt, err = txn.Prepare(pq.CopyIn(metricName, "time", "dbname", "data", "tag_data"))
			if err != nil {
				log.Errorf("Could not prepare COPY to '%s' table: %v", metricName, err)
				atomic.AddUint64(&datastoreWriteFailuresCounter, 1)
				return err
			}
		}

		for _, m := range metrics {
			jsonBytes, err := mapToJson(m.Data)
			if err != nil {
				log.Errorf("Skipping 1 metric for [%s:%s] due to JSON conversion error: %s", m.DBName, m.Metric, err)
				atomic.AddUint64(&totalMetricsDroppedCounter, 1)
				continue
			}

			if len(m.TagData) > 0 {
				jsonBytesTags, err := mapToJson(m.TagData)
				if err != nil {
					log.Errorf("Skipping 1 metric for [%s:%s] due to JSON conversion error: %s", m.DBName, m.Metric, err)
					atomic.AddUint64(&datastoreWriteFailuresCounter, 1)
					goto stmt_close
				}
				if PGSchemaType == "custom" {
					_, err = stmt.Exec(m.Time, m.DBName, m.Metric, string(jsonBytes), string(jsonBytesTags))
				} else {
					_, err = stmt.Exec(m.Time, m.DBName, string(jsonBytes), string(jsonBytesTags))
				}
				if err != nil {
					log.Errorf("Formatting metric %s data to COPY format failed for %s: %v ", m.Metric, m.DBName, err)
					atomic.AddUint64(&datastoreWriteFailuresCounter, 1)
					goto stmt_close
				}
			} else {
				if PGSchemaType == "custom" {
					_, err = stmt.Exec(m.Time, m.DBName, m.Metric, string(jsonBytes), nil)
				} else {
					_, err = stmt.Exec(m.Time, m.DBName, string(jsonBytes), nil)
				}
				if err != nil {
					log.Errorf("Formatting metric %s data to COPY format failed for %s: %v ", m.Metric, m.DBName, err)
					atomic.AddUint64(&datastoreWriteFailuresCounter, 1)
					goto stmt_close
				}
			}
		}

		_, err = stmt.Exec()
		if err != nil {
			log.Error("COPY to Postgres failed:", err)
			atomic.AddUint64(&datastoreWriteFailuresCounter, 1)
			if strings.Contains(err.Error(), "no partition") {
				log.Warning("Some metric partitions might have been removed, halting all metric storage. Trying to re-create all needed partitions on next run")
				forceRecreatePGMetricPartitions = true
			}
		}
	stmt_close:
		err = stmt.Close()
		if err != nil {
			log.Error("stmt.Close() failed:", err)
		}
	}

	t_diff := time.Since(t1)
	if err == nil {
		if len(storeMessages) == 1 {
			log.Infof("wrote %d/%d rows to Postgres for [%s:%s] in %.1f ms", rows_batched, total_rows,
				storeMessages[0].DBUniqueName, storeMessages[0].MetricName, float64(t_diff.Nanoseconds())/1000000)
		} else {
			log.Infof("wrote %d/%d rows from %d metric sets to Postgres in %.1f ms", rows_batched, total_rows,
				len(storeMessages), float64(t_diff.Nanoseconds())/1000000)
		}
		atomic.StoreInt64(&lastSuccessfulDatastoreWriteTimeEpoch, t1.Unix())
		atomic.AddUint64(&datastoreTotalWriteTimeMicroseconds, uint64(t_diff.Microseconds()))
		atomic.AddUint64(&datastoreWriteSuccessCounter, 1)
	}
	return err
}

func OldPostgresMetricsDeleter(metricAgeDaysThreshold int64, schemaType string) {
	sqlDoesOldPartListingFuncExist := `SELECT count(*) FROM information_schema.routines WHERE routine_schema = 'admin' AND routine_name = 'get_old_time_partitions'`
	oldPartListingFuncExists := false // if func existing (>v1.8.1) then use it to drop old partitions in smaller batches
	// as for large setup (50+ DBs) one could reach the default "max_locks_per_transaction" otherwise

	ret, err := DBExecRead(metricDb, METRICDB_IDENT, sqlDoesOldPartListingFuncExist)
	if err == nil && len(ret) > 0 && ret[0]["count"].(int64) > 0 {
		oldPartListingFuncExists = true
	}

	time.Sleep(time.Hour * 1) // to reduce distracting log messages at startup

	for {
		// metric|metric-time|metric-dbname-time|custom
		if schemaType == "metric" {
			rows_deleted, err := DeleteOldPostgresMetrics(metricAgeDaysThreshold)
			if err != nil {
				log.Errorf("Failed to delete old (>%d days) metrics from Postgres: %v", metricAgeDaysThreshold, err)
				time.Sleep(time.Second * 300)
				continue
			}
			log.Infof("Deleted %d old metrics rows...", rows_deleted)
		} else if schemaType == "timescale" || (!oldPartListingFuncExists && (schemaType == "metric-time" || schemaType == "metric-dbname-time")) {
			parts_dropped, err := DropOldTimePartitions(metricAgeDaysThreshold)

			if err != nil {
				log.Errorf("Failed to drop old partitions (>%d days) from Postgres: %v", metricAgeDaysThreshold, err)
				time.Sleep(time.Second * 300)
				continue
			}
			log.Infof("Dropped %d old metric partitions...", parts_dropped)
		} else if oldPartListingFuncExists && (schemaType == "metric-time" || schemaType == "metric-dbname-time") {
			partsToDrop, err := GetOldTimePartitions(metricAgeDaysThreshold)
			if err != nil {
				log.Errorf("Failed to get a listing of old (>%d days) time partitions from Postgres metrics DB - check that the admin.get_old_time_partitions() function is rolled out: %v", metricAgeDaysThreshold, err)
				time.Sleep(time.Second * 300)
				continue
			}
			if len(partsToDrop) > 0 {
				log.Infof("Dropping %d old metric partitions one by one...", len(partsToDrop))
				for _, toDrop := range partsToDrop {
					sqlDropTable := fmt.Sprintf(`DROP TABLE IF EXISTS %s`, toDrop)
					log.Debugf("Dropping old metric data partition: %s", toDrop)
					_, err := DBExecRead(metricDb, METRICDB_IDENT, sqlDropTable)
					if err != nil {
						log.Errorf("Failed to drop old partition %s from Postgres metrics DB: %v", toDrop, err)
						time.Sleep(time.Second * 300)
					} else {
						time.Sleep(time.Second * 5)
					}
				}
			} else {
				log.Infof("No old metric partitions found to drop...")
			}
		}
		time.Sleep(time.Hour * 12)
	}
}

func DeleteOldPostgresMetrics(metricAgeDaysThreshold int64) (int64, error) {
	// for 'metric' schema i.e. no time partitions
	var total_dropped int64
	get_top_lvl_tables_sql := `
	select 'public.' || quote_ident(c.relname) as table_full_name
	from pg_class c
	join pg_namespace n on n.oid = c.relnamespace
	where relkind in ('r', 'p') and nspname = 'public'
	and exists (select 1 from pg_attribute where attrelid = c.oid and attname = 'time')
	and pg_catalog.obj_description(c.oid, 'pg_class') = 'pgwatch2-generated-metric-lvl'
	order by 1
	`
	delete_sql := `
	with q_blocks_range as (
		select min(ctid), max(ctid) from (
		  select ctid from %s
			where time < (now() - '1day'::interval * %d)
			order by ctid
		  limit 5000
	    ) x
    ),
	q_deleted as (
	  delete from %s
	  where ctid between (select min from q_blocks_range) and (select max from q_blocks_range)
	  and time < (now() - '1day'::interval * %d)
	  returning *
	)
	select count(*) from q_deleted;
	`

	top_lvl_tables, err := DBExecRead(metricDb, METRICDB_IDENT, get_top_lvl_tables_sql)
	if err != nil {
		return total_dropped, err
	}

	for _, dr := range top_lvl_tables {

		log.Debugf("Dropping one chunk (max 5000 rows) of old data (if any found) from %v", dr["table_full_name"])
		sql := fmt.Sprintf(delete_sql, dr["table_full_name"].(string), metricAgeDaysThreshold, dr["table_full_name"].(string), metricAgeDaysThreshold)

		for {
			ret, err := DBExecRead(metricDb, METRICDB_IDENT, sql)
			if err != nil {
				return total_dropped, err
			}
			if ret[0]["count"].(int64) == 0 {
				break
			}
			total_dropped += ret[0]["count"].(int64)
			log.Debugf("Dropped %d rows from %v, sleeping 100ms...", ret[0]["count"].(int64), dr["table_full_name"])
			time.Sleep(time.Millisecond * 500)
		}
	}
	return total_dropped, nil
}

func DropOldTimePartitions(metricAgeDaysThreshold int64) (int, error) {
	parts_dropped := 0
	var err error
	sql_old_part := `select admin.drop_old_time_partitions($1, $2)`

	ret, err := DBExecRead(metricDb, METRICDB_IDENT, sql_old_part, metricAgeDaysThreshold, false)
	if err != nil {
		log.Error("Failed to drop old time partitions from Postgres metricDB:", err)
		return parts_dropped, err
	}
	parts_dropped = int(ret[0]["drop_old_time_partitions"].(int64))

	return parts_dropped, err
}

func GetOldTimePartitions(metricAgeDaysThreshold int64) ([]string, error) {
	partsToDrop := make([]string, 0)
	var err error
	sqlGetOldParts := `select admin.get_old_time_partitions($1)`

	ret, err := DBExecRead(metricDb, METRICDB_IDENT, sqlGetOldParts, metricAgeDaysThreshold)
	if err != nil {
		log.Error("Failed to get a listing of old time partitions from Postgres metricDB:", err)
		return partsToDrop, err
	}
	for _, row := range ret {
		partsToDrop = append(partsToDrop, row["get_old_time_partitions"].(string))
	}

	return partsToDrop, nil
}

func CheckIfPGSchemaInitializedOrFail() string {
	var partFuncSignature string
	var pgSchemaType string

	schema_type_sql := `select schema_type from admin.storage_schema_type`
	ret, err := DBExecRead(metricDb, METRICDB_IDENT, schema_type_sql)
	if err != nil {
		log.Fatal("have you initialized the metrics schema, including a row in 'storage_schema_type' table, from schema_base.sql?", err)
	}
	if err == nil && len(ret) == 0 {
		log.Fatal("no metric schema selected, no row in table 'storage_schema_type'. see the README from the 'pgwatch2/sql/metric_store' folder on choosing a schema")
	}
	pgSchemaType = ret[0]["schema_type"].(string)
	if !(pgSchemaType == "metric" || pgSchemaType == "metric-time" || pgSchemaType == "metric-dbname-time" || pgSchemaType == "custom" || pgSchemaType == "timescale") {
		log.Fatalf("Unknow Postgres schema type found from Metrics DB: %s", pgSchemaType)
	}

	if pgSchemaType == "custom" {
		sql := `
		SELECT has_table_privilege(session_user, 'public.metrics', 'INSERT') ok;
		`
		ret, err := DBExecRead(metricDb, METRICDB_IDENT, sql)
		if err != nil || (err == nil && !ret[0]["ok"].(bool)) {
			log.Fatal("public.metrics table not existing or no INSERT privileges")
		}
	} else {
		sql := `
		SELECT has_table_privilege(session_user, 'admin.metrics_template', 'INSERT') ok;
		`
		ret, err := DBExecRead(metricDb, METRICDB_IDENT, sql)
		if err != nil || (err == nil && !ret[0]["ok"].(bool)) {
			log.Fatal("admin.metrics_template table not existing or no INSERT privileges")
		}
	}

	if pgSchemaType == "metric" {
		partFuncSignature = "admin.ensure_partition_metric(text)"
	} else if pgSchemaType == "metric-time" {
		partFuncSignature = "admin.ensure_partition_metric_time(text,timestamp with time zone,integer)"
	} else if pgSchemaType == "metric-dbname-time" {
		partFuncSignature = "admin.ensure_partition_metric_dbname_time(text,text,timestamp with time zone,integer)"
	} else if pgSchemaType == "timescale" {
		partFuncSignature = "admin.ensure_partition_timescale(text)"
	}

	if partFuncSignature != "" {
		sql := `
			SELECT has_function_privilege(session_user,
				'%s',
				'execute') ok;
			`
		ret, err := DBExecRead(metricDb, METRICDB_IDENT, fmt.Sprintf(sql, partFuncSignature))
		if err != nil || (err == nil && !ret[0]["ok"].(bool)) {
			log.Fatalf("%s function not existing or no EXECUTE privileges. Have you rolled out the schema correctly from pgwatch2/sql/metric_store?", partFuncSignature)
		}
	}
	return pgSchemaType
}

func AddDBUniqueMetricToListingTable(db_unique, metric string) error {
	sql := `insert into admin.all_distinct_dbname_metrics
			select $1, $2
			where not exists (
				select * from admin.all_distinct_dbname_metrics where dbname = $1 and metric = $2
			)`
	_, err := DBExecRead(metricDb, METRICDB_IDENT, sql, db_unique, metric)
	return err
}

func UniqueDbnamesListingMaintainer(daemonMode bool) {
	// due to metrics deletion the listing can go out of sync (a trigger not really wanted)
	sql_get_advisory_lock := `SELECT pg_try_advisory_lock(1571543679778230000) AS have_lock` // 1571543679778230000 is just a random bigint
	sql_top_level_metrics := `SELECT table_name FROM admin.get_top_level_metric_tables()`
	sql_distinct := `
	WITH RECURSIVE t(dbname) AS (
		SELECT MIN(dbname) AS dbname FROM %s
		UNION
		SELECT (SELECT MIN(dbname) FROM %s WHERE dbname > t.dbname) FROM t )
	SELECT dbname FROM t WHERE dbname NOTNULL ORDER BY 1
	`
	sql_delete := `DELETE FROM admin.all_distinct_dbname_metrics WHERE NOT dbname = ANY($1) and metric = $2 RETURNING *`
	sql_delete_all := `DELETE FROM admin.all_distinct_dbname_metrics WHERE metric = $1 RETURNING *`
	sql_add := `
		INSERT INTO admin.all_distinct_dbname_metrics SELECT u, $2 FROM (select unnest($1::text[]) as u) x
		WHERE NOT EXISTS (select * from admin.all_distinct_dbname_metrics where dbname = u and metric = $2)
		RETURNING *;
	`

	for {
		if daemonMode {
			time.Sleep(time.Hour * 24)
		}

		log.Infof("Trying to get metricsDb listing maintaner advisory lock...") // to only have one "maintainer" in case of a "push" setup, as can get costly
		lock, err := DBExecRead(metricDb, METRICDB_IDENT, sql_get_advisory_lock)
		if err != nil {
			log.Error("Getting metricsDb listing maintaner advisory lock failed:", err)
			continue
		}
		if !(lock[0]["have_lock"].(bool)) {
			log.Info("Skipping admin.all_distinct_dbname_metrics maintenance as another instance has the advisory lock...")
			continue
		}

		log.Infof("Refreshing admin.all_distinct_dbname_metrics listing table...")
		all_distinct_metric_tables, err := DBExecRead(metricDb, METRICDB_IDENT, sql_top_level_metrics)
		if err != nil {
			log.Error("Could not refresh Postgres dbnames listing table:", err)
		} else {
			for _, dr := range all_distinct_metric_tables {
				found_dbnames_map := make(map[string]bool)
				found_dbnames_arr := make([]string, 0)
				metric_name := strings.Replace(dr["table_name"].(string), "public.", "", 1)

				log.Debugf("Refreshing all_distinct_dbname_metrics listing for metric: %s", metric_name)
				ret, err := DBExecRead(metricDb, METRICDB_IDENT, fmt.Sprintf(sql_distinct, dr["table_name"], dr["table_name"]))
				if err != nil {
					log.Errorf("Could not refresh Postgres all_distinct_dbname_metrics listing table for '%s': %s", metric_name, err)
					break
				}
				for _, dr_dbname := range ret {
					found_dbnames_map[dr_dbname["dbname"].(string)] = true // "set" behaviour, don't want duplicates
				}

				// delete all that are not known and add all that are not there
				for k := range found_dbnames_map {
					found_dbnames_arr = append(found_dbnames_arr, k)
				}
				if len(found_dbnames_arr) == 0 { // delete all entries for given metric
					log.Debugf("Deleting Postgres all_distinct_dbname_metrics listing table entries for metric '%s':", metric_name)
					_, err = DBExecRead(metricDb, METRICDB_IDENT, sql_delete_all, metric_name)
					if err != nil {
						log.Errorf("Could not delete Postgres all_distinct_dbname_metrics listing table entries for metric '%s': %s", metric_name, err)
					}
					continue
				}
				ret, err = DBExecRead(metricDb, METRICDB_IDENT, sql_delete, pq.Array(found_dbnames_arr), metric_name)
				if err != nil {
					log.Errorf("Could not refresh Postgres all_distinct_dbname_metrics listing table for metric '%s': %s", metric_name, err)
				} else if len(ret) > 0 {
					log.Infof("Removed %d stale entries from all_distinct_dbname_metrics listing table for metric: %s", len(ret), metric_name)
				}
				ret, err = DBExecRead(metricDb, METRICDB_IDENT, sql_add, pq.Array(found_dbnames_arr), metric_name)
				if err != nil {
					log.Errorf("Could not refresh Postgres all_distinct_dbname_metrics listing table for metric '%s': %s", metric_name, err)
				} else if len(ret) > 0 {
					log.Infof("Added %d entry to the Postgres all_distinct_dbname_metrics listing table for metric: %s", len(ret), metric_name)
				}
				if daemonMode {
					time.Sleep(time.Minute)
				}
			}
		}
		if !daemonMode {
			return
		}
	}
}

func EnsureMetricDummy(metric string) {
	if opts.Datastore != DATASTORE_POSTGRES {
		return
	}
	sql_ensure := `
	select admin.ensure_dummy_metrics_table($1) as created
	`
	PGDummyMetricTablesLock.Lock()
	defer PGDummyMetricTablesLock.Unlock()
	lastEnsureCall, ok := PGDummyMetricTables[metric]
	if ok && lastEnsureCall.After(time.Now().Add(-1*time.Hour)) {
		return
	} else {
		ret, err := DBExecRead(metricDb, METRICDB_IDENT, sql_ensure, metric)
		if err != nil {
			log.Errorf("Failed to create dummy partition of metric '%s': %v", metric, err)
		} else {
			if ret[0]["created"].(bool) {
				log.Infof("Created a dummy partition of metric '%s'", metric)
			}
			PGDummyMetricTables[metric] = time.Now()
		}
	}
}

func EnsureMetric(pg_part_bounds map[string]ExistingPartitionInfo, force bool) error {

	sql_ensure := `
	select * from admin.ensure_partition_metric($1)
	`
	for metric := range pg_part_bounds {

		_, ok := partitionMapMetric[metric] // sequential access currently so no lock needed
		if !ok || force {
			_, err := DBExecRead(metricDb, METRICDB_IDENT, sql_ensure, metric)
			if err != nil {
				log.Errorf("Failed to create partition on metric '%s': %v", metric, err)
				return err
			}
			partitionMapMetric[metric] = ExistingPartitionInfo{}
		}
	}
	return nil
}

func EnsureMetricTimescale(pg_part_bounds map[string]ExistingPartitionInfo, force bool) error {
	var err error
	sql_ensure := `
	select * from admin.ensure_partition_timescale($1)
	`
	for metric := range pg_part_bounds {
		if strings.HasSuffix(metric, "_realtime") {
			continue
		}
		_, ok := partitionMapMetric[metric]
		if !ok {
			_, err = DBExecRead(metricDb, METRICDB_IDENT, sql_ensure, metric)
			if err != nil {
				log.Errorf("Failed to create a TimescaleDB table for metric '%s': %v", metric, err)
				return err
			}
			partitionMapMetric[metric] = ExistingPartitionInfo{}
		}
	}

	err = EnsureMetricTime(pg_part_bounds, force, true)
	if err != nil {
		return err
	}
	return nil
}

func EnsureMetricTime(pg_part_bounds map[string]ExistingPartitionInfo, force bool, realtime_only bool) error {
	// TODO if less < 1d to part. end, precreate ?
	sql_ensure := `
	select * from admin.ensure_partition_metric_time($1, $2)
	`

	for metric, pb := range pg_part_bounds {
		if realtime_only && !strings.HasSuffix(metric, "_realtime") {
			continue
		}
		if pb.StartTime.IsZero() || pb.EndTime.IsZero() {
			return fmt.Errorf("zero StartTime/EndTime in partitioning request: [%s:%v]", metric, pb)
		}

		partInfo, ok := partitionMapMetric[metric]
		if !ok || (ok && (pb.StartTime.Before(partInfo.StartTime))) || force {
			ret, err := DBExecRead(metricDb, METRICDB_IDENT, sql_ensure, metric, pb.StartTime)
			if err != nil {
				log.Error("Failed to create partition on 'metrics':", err)
				return err
			}
			if !ok {
				partInfo = ExistingPartitionInfo{}
			}
			partInfo.StartTime = ret[0]["part_available_from"].(time.Time)
			partInfo.EndTime = ret[0]["part_available_to"].(time.Time)
			partitionMapMetric[metric] = partInfo
		}
		if pb.EndTime.After(partInfo.EndTime) || pb.EndTime.Equal(partInfo.EndTime) || force {
			ret, err := DBExecRead(metricDb, METRICDB_IDENT, sql_ensure, metric, pb.EndTime)
			if err != nil {
				log.Error("Failed to create partition on 'metrics':", err)
				return err
			}
			partInfo.EndTime = ret[0]["part_available_to"].(time.Time)
			partitionMapMetric[metric] = partInfo
		}
	}
	return nil
}

func EnsureMetricDbnameTime(metric_dbname_part_bounds map[string]map[string]ExistingPartitionInfo, force bool) error {
	// TODO if less < 1d to part. end, precreate ?
	sql_ensure := `
	select * from admin.ensure_partition_metric_dbname_time($1, $2, $3)
	`

	for metric, dbnameTimestampMap := range metric_dbname_part_bounds {
		_, ok := partitionMapMetricDbname[metric]
		if !ok {
			partitionMapMetricDbname[metric] = make(map[string]ExistingPartitionInfo)
		}

		for dbname, pb := range dbnameTimestampMap {

			if pb.StartTime.IsZero() || pb.EndTime.IsZero() {
				return fmt.Errorf("zero StartTime/EndTime in partitioning request: [%s:%v]", metric, pb)
			}

			partInfo, ok := partitionMapMetricDbname[metric][dbname]
			if !ok || (ok && (pb.StartTime.Before(partInfo.StartTime))) || force {
				ret, err := DBExecRead(metricDb, METRICDB_IDENT, sql_ensure, metric, dbname, pb.StartTime)
				if err != nil {
					log.Errorf("Failed to create partition for [%s:%s]: %v", metric, dbname, err)
					return err
				}
				if !ok {
					partInfo = ExistingPartitionInfo{}
				}
				partInfo.StartTime = ret[0]["part_available_from"].(time.Time)
				partInfo.EndTime = ret[0]["part_available_to"].(time.Time)
				partitionMapMetricDbname[metric][dbname] = partInfo
			}
			if pb.EndTime.After(partInfo.EndTime) || pb.EndTime.Equal(partInfo.EndTime) || force {
				ret, err := DBExecRead(metricDb, METRICDB_IDENT, sql_ensure, metric, dbname, pb.EndTime)
				if err != nil {
					log.Errorf("Failed to create partition for [%s:%s]: %v", metric, dbname, err)
					return err
				}
				partInfo.EndTime = ret[0]["part_available_to"].(time.Time)
				partitionMapMetricDbname[metric][dbname] = partInfo
			}
		}
	}
	return nil
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
	if len(data) == 0 {
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

				if strings.HasPrefix(k, TAG_PREFIX) { // ignore tags for Graphite
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
					log.Infof("Invalid (non-numeric) column type ignored: metric %s, column: %v, return type: %T", measurement, k, t)
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
	t_diff := time.Since(t1)
	if err != nil {
		atomic.AddUint64(&datastoreWriteFailuresCounter, 1)
		log.Error("could not send metric to Graphite:", err)
	} else {
		atomic.StoreInt64(&lastSuccessfulDatastoreWriteTimeEpoch, t1.Unix())
		atomic.AddUint64(&datastoreTotalWriteTimeMicroseconds, uint64(t_diff.Microseconds()))
		atomic.AddUint64(&datastoreWriteSuccessCounter, 1)
		log.Debug("Sent in ", t_diff.Microseconds(), "us")
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
	monitored_db_cache_new := make(map[string]MonitoredDatabase)

	for _, row := range data {
		monitored_db_cache_new[row.DBUniqueName] = row
	}

	monitored_db_cache_lock.Lock()
	monitored_db_cache = monitored_db_cache_new
	monitored_db_cache_lock.Unlock()
}

func ProcessRetryQueue(data_source, conn_str, conn_ident string, retry_queue *list.List, limit int) error {
	var err error
	iterations_done := 0

	for retry_queue.Len() > 0 { // send over the whole re-try queue at once if connection works
		log.Debug("Processing retry_queue", conn_ident, ". Items in retry_queue: ", retry_queue.Len())
		msg := retry_queue.Back().Value.([]MetricStoreMessage)

		if data_source == DATASTORE_INFLUX {
			err = SendToInflux(conn_str, conn_ident, msg)
		} else if data_source == DATASTORE_POSTGRES {
			err = SendToPostgres(msg)
		} else if data_source == DATASTORE_GRAPHITE {
			for _, m := range msg {
				err = SendToGraphite(m.DBUniqueName, m.MetricName, m.Data) // TODO add baching
				if err != nil {
					log.Info("Reconnect to graphite")
					InitGraphiteConnection(graphite_host, graphite_port)
				}
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
			} else if data_source == DATASTORE_INFLUX && strings.Contains(err.Error(), "partial write: max-values-per-tag limit exceeded") {
				log.Errorf("Partial write into Influx for [%s:%s], check / increase the max-values-per-tag in InfluxDB config: %v",
					msg[0].DBUniqueName, msg[0].MetricName, err)
				atomic.AddUint64(&totalMetricsDroppedCounter, 1)
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
		log.Fatalf("Check --batching-delay-ms, zero/negative batching delay:", batchingMaxDelayMillis)
	}
	var datapointCounter int = 0
	var maxBatchSize int = 1000            // flush on maxBatchSize metric points or batchingMaxDelayMillis passed
	batch := make([]MetricStoreMessage, 0) // no size limit here as limited in persister already
	ticker := time.NewTicker(time.Millisecond * time.Duration(batchingMaxDelayMillis))

	for {
		select {
		case <-ticker.C:
			if len(batch) > 0 {
				flushed := make([]MetricStoreMessage, len(batch))
				copy(flushed, batch)
				log.Debugf("Flushing %d metric datasets due to batching timeout", len(batch))
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
					log.Debugf("Flushing %d metric datasets due to maxBatchSize limit of %d datapoints", len(batch), maxBatchSize)
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

	jsonOutFile, err := os.OpenFile(jsonPath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0640)
	if err != nil {
		atomic.AddUint64(&datastoreWriteFailuresCounter, 1)
		return err
	}
	defer jsonOutFile.Close()

	log.Infof("Writing %d metric sets to JSON file at \"%s\"...", len(msgArr), jsonPath)
	enc := json.NewEncoder(jsonOutFile)
	for _, msg := range msgArr {
		dataRow := map[string]interface{}{"metric": msg.MetricName, "data": msg.Data, "dbname": msg.DBUniqueName, "custom_tags": msg.CustomTags}
		if addRealDbname && msg.RealDbname != "" {
			dataRow[opts.RealDbnameField] = msg.RealDbname
		}
		if addSystemIdentifier && msg.SystemIdentifier != "" {
			dataRow[opts.SystemIdentifierField] = msg.SystemIdentifier
		}
		err = enc.Encode(dataRow)
		if err != nil {
			atomic.AddUint64(&datastoreWriteFailuresCounter, 1)
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
					if data_store == DATASTORE_PROMETHEUS && promAsyncMode {
						if len(msg_arr) == 0 || len(msg_arr[0].Data) == 0 { // no batching in async prom mode, so using 0 indexing ok
							continue
						}
						msg := msg_arr[0]
						PromAsyncCacheAddMetricData(msg.DBUniqueName, msg.MetricName, msg_arr)
						log.Infof("[%s:%s] Added %d rows to Prom cache", msg.DBUniqueName, msg.MetricName, len(msg.Data))
					} else if data_store == DATASTORE_INFLUX {
						err = SendToInflux(InfluxConnectStrings[i], strconv.Itoa(i), msg_arr)
					} else if data_store == DATASTORE_POSTGRES {
						err = SendToPostgres(msg_arr)
						if err != nil && strings.Contains(err.Error(), "does not exist") {
							// in case data was cleaned by user externally
							log.Warning("re-initializing metric partition cache due to possible external data cleanup...")
							partitionMapMetric = make(map[string]ExistingPartitionInfo)
							partitionMapMetricDbname = make(map[string]map[string]ExistingPartitionInfo)
						}
					} else if data_store == DATASTORE_GRAPHITE {
						for _, m := range msg_arr {
							err = SendToGraphite(m.DBUniqueName, m.MetricName, m.Data) // TODO does Graphite library support batching?
							if err != nil {
								atomic.AddUint64(&datastoreWriteFailuresCounter, 1)
							}
						}
					} else if data_store == DATASTORE_JSON {
						err = WriteMetricsToJsonFile(msg_arr, opts.JsonStorageFile)
					} else {
						log.Fatal("Invalid datastore:", data_store)
					}
					last_try[i] = time.Now()

					if err != nil {
						if opts.Datastore == DATASTORE_INFLUX {
							if strings.Contains(err.Error(), "unable to parse") { // TODO move to a separate func
								if len(msg_arr) == 1 {
									log.Errorf("Dropping metric [%s:%s] as Influx is unable to parse the data: %s",
										msg_arr[0].DBUniqueName, msg_arr[0].MetricName, msg_arr[0].Data) // ignore data points consisting of anything else than strings and floats
								} else {
									log.Errorf("Dropping %d metric-sets as Influx is unable to parse the data: %s", len(msg_arr), err)
									// TODO loop over single metrics in case of errors?
								}
							} else if strings.Contains(err.Error(), "partial write: max-values-per-tag limit exceeded") {
								if len(msg_arr) == 1 {
									log.Errorf("Partial write into Influx for [%s:%s], check / increase the max-values-per-tag in InfluxDB config: %v",
										msg_arr[0].DBUniqueName, msg_arr[0].MetricName, err)
								} else {
									log.Errorf("Partial write into Influx, check / increase the max-values-per-tag in InfluxDB config: %v", err)
								}
							} else {
								log.Errorf("Failed to write into datastore %d: %s", i, err)
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

func DBGetSizeMB(dbUnique string) (int64, error) {
	sql_db_size := `select /* pgwatch2_generated */ pg_database_size(current_database());`
	var sizeMB int64

	lastDBSizeCheckLock.RLock()
	lastDBSizeCheckTime := lastDBSizeFetchTime[dbUnique]
	lastDBSize, ok := lastDBSizeMB[dbUnique]
	lastDBSizeCheckLock.RUnlock()

	if !ok || lastDBSizeCheckTime.Add(DB_SIZE_CACHING_INTERVAL).Before(time.Now()) {
		ver, err := DBGetPGVersion(dbUnique, DBTYPE_PG, false)
		if err != nil || (ver.ExecEnv != EXEC_ENV_AZURE_SINGLE) || (ver.ExecEnv == EXEC_ENV_AZURE_SINGLE && ver.ApproxDBSizeB < 1e12) {
			log.Debugf("[%s] determining DB size ...", dbUnique)

			data, err, _ := DBExecReadByDbUniqueName(dbUnique, "", 300, sql_db_size) // can take some time on ancient FS, use 300s stmt timeout
			if err != nil {
				log.Errorf("[%s] failed to determine DB size...cannot apply --min-db-size-mb flag. err: %v ...", dbUnique, err)
				return 0, err
			}
			sizeMB = data[0]["pg_database_size"].(int64) / 1048576
		} else {
			log.Debugf("[%s] Using approx DB size for the --min-db-size-mb filter ...", dbUnique)
			sizeMB = ver.ApproxDBSizeB / 1048576
		}

		log.Debugf("[%s] DB size = %d MB, caching for %v ...", dbUnique, sizeMB, DB_SIZE_CACHING_INTERVAL)

		lastDBSizeCheckLock.Lock()
		lastDBSizeFetchTime[dbUnique] = time.Now()
		lastDBSizeMB[dbUnique] = sizeMB
		lastDBSizeCheckLock.Unlock()

		return sizeMB, nil

	}
	log.Debugf("[%s] using cached DBsize %d MB for the --min-db-size-mb filter check", dbUnique, lastDBSize)
	return lastDBSize, nil
}

func TryDiscoverExecutionEnv(dbUnique string) string {
	sqlPGExecEnv := `select /* pgwatch2_generated */
	case
	  when exists (select * from pg_settings where name = 'pg_qs.host_database' and setting = 'azure_sys') and version() ~* 'compiled by Visual C' then 'AZURE_SINGLE'
	  when exists (select * from pg_settings where name = 'pg_qs.host_database' and setting = 'azure_sys') and version() ~* 'compiled by gcc' then 'AZURE_FLEXIBLE'
	  when exists (select * from pg_settings where name = 'cloudsql.supported_extensions') then 'GOOGLE'
	else
	  'UNKNOWN'
	end as exec_env;
  `
	data, err, _ := DBExecReadByDbUniqueName(dbUnique, "", 0, sqlPGExecEnv)
	if err != nil {
		return ""
	}
	return data[0]["exec_env"].(string)
}

func GetDBTotalApproxSize(dbUnique string) (int64, error) {
	sqlApproxDBSize := `
	select /* pgwatch2_generated */
		current_setting('block_size')::int8 * sum(relpages) as db_size_approx
	from
		pg_class c
	where	/* NB! works only for v9.1+*/
		c.relpersistence != 't';
	`
	data, err, _ := DBExecReadByDbUniqueName(dbUnique, "", 0, sqlApproxDBSize)
	if err != nil {
		return 0, err
	}
	return data[0]["db_size_approx"].(int64), nil
}

func DBGetPGVersion(dbUnique string, dbType string, noCache bool) (DBVersionMapEntry, error) {
	var ver DBVersionMapEntry
	var verNew DBVersionMapEntry
	var ok bool
	sql := `
		select /* pgwatch2_generated */ (regexp_matches(
			regexp_replace(current_setting('server_version'), '(beta|devel).*', '', 'g'),
			E'\\d+\\.?\\d+?')
			)[1]::text as ver, pg_is_in_recovery(), current_database()::text;
	`
	sql_sysid := `select /* pgwatch2_generated */ system_identifier::text from pg_control_system();`
	sql_su := `select /* pgwatch2_generated */ rolsuper
			   from pg_roles r where rolname = session_user;`
	sql_extensions := `select /* pgwatch2_generated */ extname::text, (regexp_matches(extversion, $$\d+\.?\d+?$$))[1]::text as extversion from pg_extension order by 1;`
	pgpool_version := `SHOW POOL_VERSION` // supported from pgpool2 v3.0

	db_pg_version_map_lock.Lock()
	get_ver_lock, ok := db_get_pg_version_map_lock[dbUnique]
	if !ok {
		db_get_pg_version_map_lock[dbUnique] = sync.RWMutex{}
		get_ver_lock = db_get_pg_version_map_lock[dbUnique]
	}
	ver, ok = db_pg_version_map[dbUnique]
	db_pg_version_map_lock.Unlock()

	if !noCache && ok && ver.LastCheckedOn.After(time.Now().Add(time.Minute*-2)) { // use cached version for 2 min
		//log.Debugf("using cached postgres version %s for %s", ver.Version.String(), dbUnique)
		return ver, nil
	} else {
		get_ver_lock.Lock() // limit to 1 concurrent version info fetch per DB
		defer get_ver_lock.Unlock()
		log.Debugf("[%s][%s] determining DB version and recovery status...", dbUnique, dbType)

		if verNew.Extensions == nil {
			verNew.Extensions = make(map[string]decimal.Decimal)
		}

		if dbType == DBTYPE_BOUNCER {
			data, err, _ := DBExecReadByDbUniqueName(dbUnique, "", 0, "show version")
			if err != nil {
				return verNew, err
			}
			if len(data) == 0 {
				// surprisingly pgbouncer 'show version' outputs in pre v1.12 is emitted as 'NOTICE' which cannot be accessed from Go lib/pg
				verNew.Version, _ = decimal.NewFromString("0")
				verNew.VersionStr = "0"
			} else {
				matches := rBouncerAndPgpoolVerMatch.FindStringSubmatch(data[0]["version"].(string))
				if len(matches) != 1 {
					log.Errorf("[%s] Unexpected PgBouncer version input: %s", dbUnique, data[0]["version"].(string))
					return ver, fmt.Errorf("Unexpected PgBouncer version input: %s", data[0]["version"].(string))
				}
				verNew.VersionStr = matches[0]
				verNew.Version, _ = decimal.NewFromString(matches[0])
			}
		} else if dbType == DBTYPE_PGPOOL {
			data, err, _ := DBExecReadByDbUniqueName(dbUnique, "", 0, pgpool_version)
			if err != nil {
				return verNew, err
			}
			if len(data) == 0 {
				verNew.Version, _ = decimal.NewFromString("3.0")
				verNew.VersionStr = "3.0"
			} else {
				matches := rBouncerAndPgpoolVerMatch.FindStringSubmatch(string(data[0]["pool_version"].([]byte)))
				if len(matches) != 1 {
					log.Errorf("[%s] Unexpected PgPool version input: %s", dbUnique, data[0]["pool_version"].([]byte))
					return ver, fmt.Errorf("Unexpected PgPool version input: %s", data[0]["pool_version"].([]byte))
				}
				verNew.VersionStr = matches[0]
				verNew.Version, _ = decimal.NewFromString(matches[0])
			}
		} else {
			data, err, _ := DBExecReadByDbUniqueName(dbUnique, "", 0, sql)
			if err != nil {
				if noCache {
					return ver, err
				} else {
					log.Infof("[%s] DBGetPGVersion failed, using old cached value. err: %v", dbUnique, err)
					return ver, nil
				}
			}
			verNew.Version, _ = decimal.NewFromString(data[0]["ver"].(string))
			verNew.VersionStr = data[0]["ver"].(string)
			verNew.IsInRecovery = data[0]["pg_is_in_recovery"].(bool)
			verNew.RealDbname = data[0]["current_database"].(string)

			if verNew.Version.GreaterThanOrEqual(decimal.NewFromFloat(10)) && addSystemIdentifier {
				log.Debugf("[%s] determining system identifier version (pg ver: %v)", dbUnique, verNew.VersionStr)
				data, err, _ := DBExecReadByDbUniqueName(dbUnique, "", 0, sql_sysid)
				if err == nil && len(data) > 0 {
					verNew.SystemIdentifier = data[0]["system_identifier"].(string)
				}
			}

			if ver.ExecEnv != "" {
				verNew.ExecEnv = ver.ExecEnv // carry over as not likely to change ever
			} else {
				log.Debugf("[%s] determining the execution env...", dbUnique)
				execEnv := TryDiscoverExecutionEnv(dbUnique)
				if execEnv != "" {
					log.Debugf("[%s] running on execution env: %s", dbUnique, execEnv)
					verNew.ExecEnv = execEnv
				}
			}

			// to work around poor Azure Single Server FS functions performance for some metrics + the --min-db-size-mb filter
			if verNew.ExecEnv == EXEC_ENV_AZURE_SINGLE {
				approxSize, err := GetDBTotalApproxSize(dbUnique)
				if err == nil {
					verNew.ApproxDBSizeB = approxSize
				} else {
					verNew.ApproxDBSizeB = ver.ApproxDBSizeB
				}
			}

			log.Debugf("[%s] determining if monitoring user is a superuser...", dbUnique)
			data, err, _ = DBExecReadByDbUniqueName(dbUnique, "", 0, sql_su)
			if err == nil {
				verNew.IsSuperuser = data[0]["rolsuper"].(bool)
			}
			log.Debugf("[%s] superuser=%v", dbUnique, verNew.IsSuperuser)

			if verNew.Version.GreaterThanOrEqual(MinExtensionInfoAvailable) {
				//log.Debugf("[%s] determining installed extensions info...", dbUnique)
				data, err, _ = DBExecReadByDbUniqueName(dbUnique, "", 0, sql_extensions)
				if err != nil {
					log.Errorf("[%s] failed to determine installed extensions info: %v", dbUnique, err)
				} else {
					for _, dr := range data {
						extver, err := decimal.NewFromString(dr["extversion"].(string))
						if err != nil {
							log.Errorf("[%s] failed to determine extension version info for extension %s: %v", dbUnique, dr["extname"], err)
							continue
						}
						verNew.Extensions[dr["extname"].(string)] = extver
					}
					log.Debugf("[%s] installed extensions: %+v", dbUnique, verNew.Extensions)
				}
			}
		}

		verNew.LastCheckedOn = time.Now()
		db_pg_version_map_lock.Lock()
		db_pg_version_map[dbUnique] = verNew
		db_pg_version_map_lock.Unlock()
	}
	return verNew, nil
}

// Need to define a sort interface as Go doesn't have support for Numeric/Decimal
type Decimal []decimal.Decimal

func (a Decimal) Len() int           { return len(a) }
func (a Decimal) Swap(i, j int)      { a[i], a[j] = a[j], a[i] }
func (a Decimal) Less(i, j int) bool { return a[i].LessThan(a[j]) }

// assumes upwards compatibility for versions
func GetMetricVersionProperties(metric string, vme DBVersionMapEntry, metricDefMap map[string]map[decimal.Decimal]MetricVersionProperties) (MetricVersionProperties, error) {
	var keys []decimal.Decimal
	var mdm map[string]map[decimal.Decimal]MetricVersionProperties

	if metricDefMap != nil {
		mdm = metricDefMap
	} else {
		metric_def_map_lock.RLock()
		mdm = deepCopyMetricDefinitionMap(metric_def_map) // copy of global cache
		metric_def_map_lock.RUnlock()
	}

	_, ok := mdm[metric]
	if !ok || len(mdm[metric]) == 0 {
		log.Debug("metric", metric, "not found")
		return MetricVersionProperties{}, errors.New("metric SQL not found")
	}

	for k := range mdm[metric] {
		keys = append(keys, k)
	}

	sort.Sort(Decimal(keys))

	var best_ver decimal.Decimal
	var min_ver decimal.Decimal
	var found bool
	for _, ver := range keys {
		if vme.Version.GreaterThanOrEqual(ver) {
			best_ver = ver
			found = true
		}
		if min_ver.IsZero() || ver.LessThan(min_ver) {
			min_ver = ver
		}
	}

	if !found {
		if vme.Version.LessThan(min_ver) { // metric not yet available for given PG ver
			return MetricVersionProperties{}, fmt.Errorf("no suitable SQL found for metric \"%s\", server version \"%s\" too old. min defined SQL ver: %s", metric, vme.VersionStr, min_ver.String())
		}
		return MetricVersionProperties{}, fmt.Errorf("no suitable SQL found for metric \"%s\", version \"%s\"", metric, vme.VersionStr)
	}

	ret := mdm[metric][best_ver]

	// check if SQL def. override defined for some specific extension version and replace the metric SQL-s if so
	if ret.MetricAttrs.ExtensionVersionOverrides != nil && len(ret.MetricAttrs.ExtensionVersionOverrides) > 0 {
		if vme.Extensions != nil && len(vme.Extensions) > 0 {
			log.Debugf("[%s] extension version based override request found: %+v", metric, ret.MetricAttrs.ExtensionVersionOverrides)
			for _, extOverride := range ret.MetricAttrs.ExtensionVersionOverrides {
				var matching = true
				for _, extVer := range extOverride.ExpectedExtensionVersions { // "natural" sorting of metric definition assumed
					installedExtVer, ok := vme.Extensions[extVer.ExtName]
					if !ok || !installedExtVer.GreaterThanOrEqual(extVer.ExtMinVersion) {
						matching = false
					}
				}
				if matching { // all defined extensions / versions (if many) need to match
					_, ok := mdm[extOverride.TargetMetric]
					if !ok {
						log.Warningf("extension based override metric not found for metric %s. substitute metric name: %s", metric, extOverride.TargetMetric)
						continue
					}
					mvp, err := GetMetricVersionProperties(extOverride.TargetMetric, vme, mdm)
					if err != nil {
						log.Warningf("undefined extension based override for metric %s, substitute metric name: %s, version: %s not found", metric, extOverride.TargetMetric, best_ver)
						continue
					}
					log.Debugf("overriding metric %s based on the extension_version_based_overrides metric attribute with %s:%s", metric, extOverride.TargetMetric, best_ver)
					if mvp.Sql != "" {
						ret.Sql = mvp.Sql
					}
					if mvp.SqlSU != "" {
						ret.SqlSU = mvp.SqlSU
					}
				}
			}
		}
	}
	return ret, nil
}

func DetectSprocChanges(dbUnique string, vme DBVersionMapEntry, storage_ch chan<- []MetricStoreMessage, host_state map[string]map[string]string) ChangeDetectionResults {
	detected_changes := make([](map[string]interface{}), 0)
	var first_run bool
	var change_counts ChangeDetectionResults

	log.Debugf("[%s][%s] checking for sproc changes...", dbUnique, SPECIAL_METRIC_CHANGE_EVENTS)
	if _, ok := host_state["sproc_hashes"]; !ok {
		first_run = true
		host_state["sproc_hashes"] = make(map[string]string)
	}

	mvp, err := GetMetricVersionProperties("sproc_hashes", vme, nil)
	if err != nil {
		log.Error("could not get sproc_hashes sql:", err)
		return change_counts
	}

	data, err, _ := DBExecReadByDbUniqueName(dbUnique, "sproc_hashes", mvp.MetricAttrs.StatementTimeoutSeconds, mvp.Sql)
	if err != nil {
		log.Error("could not read sproc_hashes from monitored host: ", dbUnique, ", err:", err)
		return change_counts
	}

	for _, dr := range data {
		obj_ident := dr["tag_sproc"].(string) + DB_METRIC_JOIN_STR + dr["tag_oid"].(string)
		prev_hash, ok := host_state["sproc_hashes"][obj_ident]
		if ok { // we have existing state
			if prev_hash != dr["md5"].(string) {
				log.Info("detected change in sproc:", dr["tag_sproc"], ", oid:", dr["tag_oid"])
				dr["event"] = "alter"
				detected_changes = append(detected_changes, dr)
				host_state["sproc_hashes"][obj_ident] = dr["md5"].(string)
				change_counts.Altered += 1
			}
		} else { // check for new / delete
			if !first_run {
				log.Info("detected new sproc:", dr["tag_sproc"], ", oid:", dr["tag_oid"])
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
			current_oid_map[dr["tag_sproc"].(string)+DB_METRIC_JOIN_STR+dr["tag_oid"].(string)] = true
		}
		for sproc_ident := range host_state["sproc_hashes"] {
			_, ok := current_oid_map[sproc_ident]
			if !ok {
				splits := strings.Split(sproc_ident, DB_METRIC_JOIN_STR)
				log.Info("detected delete of sproc:", splits[0], ", oid:", splits[1])
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
	log.Debugf("[%s][%s] detected %d sproc changes", dbUnique, SPECIAL_METRIC_CHANGE_EVENTS, len(detected_changes))
	if len(detected_changes) > 0 {
		md, _ := GetMonitoredDatabaseByUniqueName(dbUnique)
		storage_ch <- []MetricStoreMessage{MetricStoreMessage{DBUniqueName: dbUnique, MetricName: "sproc_changes", Data: detected_changes, CustomTags: md.CustomTags}}
	} else if opts.Datastore == DATASTORE_POSTGRES && first_run {
		EnsureMetricDummy("sproc_changes")
	}

	return change_counts
}

func DetectTableChanges(dbUnique string, vme DBVersionMapEntry, storage_ch chan<- []MetricStoreMessage, host_state map[string]map[string]string) ChangeDetectionResults {
	detected_changes := make([](map[string]interface{}), 0)
	var first_run bool
	var change_counts ChangeDetectionResults

	log.Debugf("[%s][%s] checking for table changes...", dbUnique, SPECIAL_METRIC_CHANGE_EVENTS)
	if _, ok := host_state["table_hashes"]; !ok {
		first_run = true
		host_state["table_hashes"] = make(map[string]string)
	}

	mvp, err := GetMetricVersionProperties("table_hashes", vme, nil)
	if err != nil {
		log.Error("could not get table_hashes sql:", err)
		return change_counts
	}

	data, err, _ := DBExecReadByDbUniqueName(dbUnique, "table_hashes", mvp.MetricAttrs.StatementTimeoutSeconds, mvp.Sql)
	if err != nil {
		log.Error("could not read table_hashes from monitored host:", dbUnique, ", err:", err)
		return change_counts
	}

	for _, dr := range data {
		obj_ident := dr["tag_table"].(string)
		prev_hash, ok := host_state["table_hashes"][obj_ident]
		//log.Debug("inspecting table:", obj_ident, "hash:", prev_hash)
		if ok { // we have existing state
			if prev_hash != dr["md5"].(string) {
				log.Info("detected DDL change in table:", dr["tag_table"])
				dr["event"] = "alter"
				detected_changes = append(detected_changes, dr)
				host_state["table_hashes"][obj_ident] = dr["md5"].(string)
				change_counts.Altered += 1
			}
		} else { // check for new / delete
			if !first_run {
				log.Info("detected new table:", dr["tag_table"])
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
		for table := range host_state["table_hashes"] {
			_, ok := current_table_map[table]
			if !ok {
				log.Info("detected drop of table:", table)
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

	log.Debugf("[%s][%s] detected %d table changes", dbUnique, SPECIAL_METRIC_CHANGE_EVENTS, len(detected_changes))
	if len(detected_changes) > 0 {
		md, _ := GetMonitoredDatabaseByUniqueName(dbUnique)
		storage_ch <- []MetricStoreMessage{MetricStoreMessage{DBUniqueName: dbUnique, MetricName: "table_changes", Data: detected_changes, CustomTags: md.CustomTags}}
	} else if opts.Datastore == DATASTORE_POSTGRES && first_run {
		EnsureMetricDummy("table_changes")
	}

	return change_counts
}

func DetectIndexChanges(dbUnique string, vme DBVersionMapEntry, storage_ch chan<- []MetricStoreMessage, host_state map[string]map[string]string) ChangeDetectionResults {
	detected_changes := make([](map[string]interface{}), 0)
	var first_run bool
	var change_counts ChangeDetectionResults

	log.Debugf("[%s][%s] checking for index changes...", dbUnique, SPECIAL_METRIC_CHANGE_EVENTS)
	if _, ok := host_state["index_hashes"]; !ok {
		first_run = true
		host_state["index_hashes"] = make(map[string]string)
	}

	mvp, err := GetMetricVersionProperties("index_hashes", vme, nil)
	if err != nil {
		log.Error("could not get index_hashes sql:", err)
		return change_counts
	}

	data, err, _ := DBExecReadByDbUniqueName(dbUnique, "index_hashes", mvp.MetricAttrs.StatementTimeoutSeconds, mvp.Sql)
	if err != nil {
		log.Error("could not read index_hashes from monitored host:", dbUnique, ", err:", err)
		return change_counts
	}

	for _, dr := range data {
		obj_ident := dr["tag_index"].(string)
		prev_hash, ok := host_state["index_hashes"][obj_ident]
		if ok { // we have existing state
			if prev_hash != (dr["md5"].(string) + dr["is_valid"].(string)) {
				log.Info("detected index change:", dr["tag_index"], ", table:", dr["table"])
				dr["event"] = "alter"
				detected_changes = append(detected_changes, dr)
				host_state["index_hashes"][obj_ident] = dr["md5"].(string) + dr["is_valid"].(string)
				change_counts.Altered += 1
			}
		} else { // check for new / delete
			if !first_run {
				log.Info("detected new index:", dr["tag_index"])
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
		for index_name := range host_state["index_hashes"] {
			_, ok := current_index_map[index_name]
			if !ok {
				log.Info("detected drop of index_name:", index_name)
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
	log.Debugf("[%s][%s] detected %d index changes", dbUnique, SPECIAL_METRIC_CHANGE_EVENTS, len(detected_changes))
	if len(detected_changes) > 0 {
		md, _ := GetMonitoredDatabaseByUniqueName(dbUnique)
		storage_ch <- []MetricStoreMessage{MetricStoreMessage{DBUniqueName: dbUnique, MetricName: "index_changes", Data: detected_changes, CustomTags: md.CustomTags}}
	} else if opts.Datastore == DATASTORE_POSTGRES && first_run {
		EnsureMetricDummy("index_changes")
	}

	return change_counts
}

func DetectPrivilegeChanges(dbUnique string, vme DBVersionMapEntry, storage_ch chan<- []MetricStoreMessage, host_state map[string]map[string]string) ChangeDetectionResults {
	detected_changes := make([](map[string]interface{}), 0)
	var first_run bool
	var change_counts ChangeDetectionResults

	log.Debugf("[%s][%s] checking object privilege changes...", dbUnique, SPECIAL_METRIC_CHANGE_EVENTS)
	if _, ok := host_state["object_privileges"]; !ok {
		first_run = true
		host_state["object_privileges"] = make(map[string]string)
	}

	mvp, err := GetMetricVersionProperties("privilege_changes", vme, nil)
	if err != nil || mvp.Sql == "" {
		log.Warningf("[%s][%s] could not get SQL for 'privilege_changes'. cannot detect privilege changes", dbUnique, SPECIAL_METRIC_CHANGE_EVENTS)
		return change_counts
	}

	// returns rows of: object_type, tag_role, tag_object, privilege_type
	data, err, _ := DBExecReadByDbUniqueName(dbUnique, "privilege_changes", mvp.MetricAttrs.StatementTimeoutSeconds, mvp.Sql)
	if err != nil {
		log.Errorf("[%s][%s] failed to fetch object privileges info: %v", dbUnique, SPECIAL_METRIC_CHANGE_EVENTS, err)
		return change_counts
	}

	current_state := make(map[string]bool)
	for _, dr := range data {
		obj_ident := fmt.Sprintf("%s#:#%s#:#%s#:#%s", dr["object_type"], dr["tag_role"], dr["tag_object"], dr["privilege_type"])
		if first_run {
			host_state["object_privileges"][obj_ident] = ""
		} else {
			_, ok := host_state["object_privileges"][obj_ident]
			if !ok {
				log.Infof("[%s][%s] detected new object privileges: role=%s, object_type=%s, object=%s, privilege_type=%s",
					dbUnique, SPECIAL_METRIC_CHANGE_EVENTS, dr["tag_role"], dr["object_type"], dr["tag_object"], dr["privilege_type"])
				dr["event"] = "GRANT"
				detected_changes = append(detected_changes, dr)
				change_counts.Created += 1
				host_state["object_privileges"][obj_ident] = ""
			}
			current_state[obj_ident] = true
		}
	}
	// check revokes - exists in old state only
	if !first_run && len(current_state) > 0 {
		for obj_prev_run := range host_state["object_privileges"] {
			if _, ok := current_state[obj_prev_run]; !ok {
				splits := strings.Split(obj_prev_run, "#:#")
				log.Infof("[%s][%s] detected removed object privileges: role=%s, object_type=%s, object=%s, privilege_type=%s",
					dbUnique, SPECIAL_METRIC_CHANGE_EVENTS, splits[1], splits[0], splits[2], splits[3])
				revoke_entry := make(map[string]interface{})
				if epoch_ns, ok := data[0]["epoch_ns"]; ok {
					revoke_entry["epoch_ns"] = epoch_ns
				} else {
					revoke_entry["epoch_ns"] = time.Now().UnixNano()
				}
				revoke_entry["object_type"] = splits[0]
				revoke_entry["tag_role"] = splits[1]
				revoke_entry["tag_object"] = splits[2]
				revoke_entry["privilege_type"] = splits[3]
				revoke_entry["event"] = "REVOKE"
				detected_changes = append(detected_changes, revoke_entry)
				change_counts.Dropped += 1
				delete(host_state["object_privileges"], obj_prev_run)
			}
		}
	}

	if opts.Datastore == DATASTORE_POSTGRES && first_run {
		EnsureMetricDummy("privilege_changes")
	}
	log.Debugf("[%s][%s] detected %d object privilege changes...", dbUnique, SPECIAL_METRIC_CHANGE_EVENTS, len(detected_changes))
	if len(detected_changes) > 0 {
		md, _ := GetMonitoredDatabaseByUniqueName(dbUnique)
		storage_ch <- []MetricStoreMessage{MetricStoreMessage{DBUniqueName: dbUnique, MetricName: "privilege_changes", Data: detected_changes, CustomTags: md.CustomTags}}
	}

	return change_counts
}

func DetectConfigurationChanges(dbUnique string, vme DBVersionMapEntry, storage_ch chan<- []MetricStoreMessage, host_state map[string]map[string]string) ChangeDetectionResults {
	detected_changes := make([](map[string]interface{}), 0)
	var first_run bool
	var change_counts ChangeDetectionResults

	log.Debugf("[%s][%s] checking for configuration changes...", dbUnique, SPECIAL_METRIC_CHANGE_EVENTS)
	if _, ok := host_state["configuration_hashes"]; !ok {
		first_run = true
		host_state["configuration_hashes"] = make(map[string]string)
	}

	mvp, err := GetMetricVersionProperties("configuration_hashes", vme, nil)
	if err != nil {
		log.Errorf("[%s][%s] could not get configuration_hashes sql: %v", dbUnique, SPECIAL_METRIC_CHANGE_EVENTS, err)
		return change_counts
	}

	data, err, _ := DBExecReadByDbUniqueName(dbUnique, "configuration_hashes", mvp.MetricAttrs.StatementTimeoutSeconds, mvp.Sql)
	if err != nil {
		log.Errorf("[%s][%s] could not read configuration_hashes from monitored host: %v", dbUnique, SPECIAL_METRIC_CHANGE_EVENTS, err)
		return change_counts
	}

	for _, dr := range data {
		obj_ident := dr["tag_setting"].(string)
		obj_value := dr["value"].(string)
		prev_hash, ok := host_state["configuration_hashes"][obj_ident]
		if ok { // we have existing state
			if prev_hash != obj_value {
				if obj_ident == "connection_ID" {
					continue // ignore some weird Azure managed PG service setting
				}
				log.Warningf("[%s][%s] detected settings change: %s = %s (prev: %s)",
					dbUnique, SPECIAL_METRIC_CHANGE_EVENTS, obj_ident, obj_value, prev_hash)
				dr["event"] = "alter"
				detected_changes = append(detected_changes, dr)
				host_state["configuration_hashes"][obj_ident] = obj_value
				change_counts.Altered += 1
			}
		} else { // check for new, delete not relevant here (pg_upgrade)
			if !first_run {
				log.Warningf("[%s][%s] detected new setting: %s", dbUnique, SPECIAL_METRIC_CHANGE_EVENTS, obj_ident)
				dr["event"] = "create"
				detected_changes = append(detected_changes, dr)
				change_counts.Created += 1
			}
			host_state["configuration_hashes"][obj_ident] = obj_value
		}
	}

	log.Debugf("[%s][%s] detected %d configuration changes", dbUnique, SPECIAL_METRIC_CHANGE_EVENTS, len(detected_changes))
	if len(detected_changes) > 0 {
		md, _ := GetMonitoredDatabaseByUniqueName(dbUnique)
		storage_ch <- []MetricStoreMessage{MetricStoreMessage{DBUniqueName: dbUnique, MetricName: "configuration_changes", Data: detected_changes, CustomTags: md.CustomTags}}
	} else if opts.Datastore == DATASTORE_POSTGRES {
		EnsureMetricDummy("configuration_changes")
	}

	return change_counts
}

func GetAllRecoMetricsForVersion(vme DBVersionMapEntry) map[string]MetricVersionProperties {
	mvp_map := make(map[string]MetricVersionProperties)

	metric_def_map_lock.RLock()
	defer metric_def_map_lock.RUnlock()
	for m := range metric_def_map {
		if strings.HasPrefix(m, RECO_PREFIX) {
			mvp, err := GetMetricVersionProperties(m, vme, metric_def_map)
			if err != nil {
				log.Warningf("Could not get SQL definition for metric \"%s\", PG %s", m, vme.VersionStr)
			} else if !mvp.MetricAttrs.IsPrivate {
				mvp_map[m] = mvp
			}
		}
	}
	return mvp_map
}

func GetRecommendations(dbUnique string, vme DBVersionMapEntry) ([]map[string]interface{}, error, time.Duration) {
	ret_data := make([]map[string]interface{}, 0)
	var total_duration time.Duration
	start_time_epoch_ns := time.Now().UnixNano()

	reco_metrics := GetAllRecoMetricsForVersion(vme)
	log.Debugf("Processing %d recommendation metrics for \"%s\"", len(reco_metrics), dbUnique)

	for m, mvp := range reco_metrics {
		data, err, duration := DBExecReadByDbUniqueName(dbUnique, m, mvp.MetricAttrs.StatementTimeoutSeconds, mvp.Sql)
		total_duration += duration
		if err != nil {
			if strings.Contains(err.Error(), "does not exist") { // some more exotic extensions missing is expected, don't pollute the error log
				log.Infof("[%s:%s] Could not execute recommendations SQL: %v", dbUnique, m, err)
			} else {
				log.Errorf("[%s:%s] Could not execute recommendations SQL: %v", dbUnique, m, err)
			}
			continue
		}
		for _, d := range data {
			d[EPOCH_COLUMN_NAME] = start_time_epoch_ns
			d["major_ver"] = PgVersionDecimalToMajorVerFloat(dbUnique, vme.Version)
			ret_data = append(ret_data, d)
		}
	}
	if len(ret_data) == 0 { // insert a dummy entry minimally so that Grafana can show at least a dropdown
		dummy := make(map[string]interface{})
		dummy["tag_reco_topic"] = "dummy"
		dummy["tag_object_name"] = "-"
		dummy["recommendation"] = "no recommendations"
		dummy[EPOCH_COLUMN_NAME] = start_time_epoch_ns
		dummy["major_ver"] = PgVersionDecimalToMajorVerFloat(dbUnique, vme.Version)
		ret_data = append(ret_data, dummy)
	}
	return ret_data, nil, total_duration
}

func PgVersionDecimalToMajorVerFloat(dbUnique string, pgVer decimal.Decimal) float64 {
	ver_float, _ := pgVer.Float64()

	if ver_float >= 10 {
		return math.Floor(ver_float)
	} else {
		return ver_float
	}
}

func CheckForPGObjectChangesAndStore(dbUnique string, vme DBVersionMapEntry, storage_ch chan<- []MetricStoreMessage, host_state map[string]map[string]string) {
	sproc_counts := DetectSprocChanges(dbUnique, vme, storage_ch, host_state) // TODO some of Detect*() code could be unified...
	table_counts := DetectTableChanges(dbUnique, vme, storage_ch, host_state)
	index_counts := DetectIndexChanges(dbUnique, vme, storage_ch, host_state)
	conf_counts := DetectConfigurationChanges(dbUnique, vme, storage_ch, host_state)
	priv_change_counts := DetectPrivilegeChanges(dbUnique, vme, storage_ch, host_state)

	if opts.Datastore == DATASTORE_POSTGRES {
		EnsureMetricDummy("object_changes")
	}

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
	if priv_change_counts.Dropped > 0 || priv_change_counts.Created > 0 {
		message += fmt.Sprintf(" privileges %d/%d/%d", priv_change_counts.Created, priv_change_counts.Altered, priv_change_counts.Dropped)
	}

	if message > "" {
		message = "Detected changes for \"" + dbUnique + "\" [Created/Altered/Dropped]:" + message
		log.Info(message)
		detected_changes_summary := make([](map[string]interface{}), 0)
		influx_entry := make(map[string]interface{})
		influx_entry["details"] = message
		influx_entry["epoch_ns"] = time.Now().UnixNano()
		detected_changes_summary = append(detected_changes_summary, influx_entry)
		md, _ := GetMonitoredDatabaseByUniqueName(dbUnique)
		storage_ch <- []MetricStoreMessage{MetricStoreMessage{DBUniqueName: dbUnique, DBType: md.DBType, MetricName: "object_changes", Data: detected_changes_summary, CustomTags: md.CustomTags}}
	}
}

func FilterPgbouncerData(data []map[string]interface{}, databaseToKeep string, vme DBVersionMapEntry) []map[string]interface{} {
	filtered_data := make([]map[string]interface{}, 0)

	for _, dr := range data {
		//log.Debugf("bouncer dr: %+v", dr)
		if _, ok := dr["database"]; !ok {
			log.Warning("Expected 'database' key not found from pgbouncer_stats, not storing data")
			continue
		}
		if (len(databaseToKeep) > 0 && dr["database"] != databaseToKeep) || dr["database"] == "pgbouncer" { // always ignore the internal 'pgbouncer' DB
			log.Debugf("Skipping bouncer stats for pool entry %v as not the specified DBName of %s", dr["database"], databaseToKeep)
			continue // and all others also if a DB / pool name was specified in config
		}

		dr["tag_database"] = dr["database"] // support multiple databases / pools via tags if DbName left empty
		delete(dr, "database")              // remove the original pool name

		if vme.Version.GreaterThanOrEqual(pgBouncerNumericCountersStartVersion) { // v1.12 counters are of type numeric instead of int64
			for k, v := range dr {
				if k == "tag_database" {
					continue
				}
				decimalCounter, err := decimal.NewFromString(string(v.([]uint8)))
				if err != nil {
					log.Errorf("Could not parse \"%+v\" to Decimal: %s", string(v.([]uint8)), err)
					return filtered_data
				}
				dr[k] = decimalCounter.IntPart() // technically could cause overflow...but highly unlikely for 2^63
			}
		}
		filtered_data = append(filtered_data, dr)
	}

	return filtered_data
}

// some extra work needed as pgpool SHOW commands don't specify the return data types for some reason
func FetchMetricsPgpool(msg MetricFetchMessage, vme DBVersionMapEntry, mvp MetricVersionProperties) ([]map[string]interface{}, error, time.Duration) {
	var ret_data = make([]map[string]interface{}, 0)
	var duration time.Duration
	epoch_ns := time.Now().UnixNano()

	sql_lines := strings.Split(strings.ToUpper(mvp.Sql), "\n")

	for _, sql := range sql_lines {
		if strings.HasPrefix(sql, "SHOW POOL_NODES") {
			data, err, dur := DBExecReadByDbUniqueName(msg.DBUniqueName, msg.MetricName, 0, sql)
			duration = duration + dur
			if err != nil {
				log.Errorf("[%s][%s] Could not fetch PgPool statistics: %v", msg.DBUniqueName, msg.MetricName, err)
				return data, err, duration
			}

			for _, row := range data {
				ret_row := make(map[string]interface{})
				ret_row[EPOCH_COLUMN_NAME] = epoch_ns
				for k, v := range row {
					vs := string(v.([]byte))
					// need 1 tag so that Influx would not merge rows
					if k == "node_id" {
						ret_row["tag_node_id"] = vs
						continue
					}

					ret_row[k] = vs
					if k == "status" { // was changed from numeric to string at some pgpool version so leave the string
						// but also add "status_num" field
						if vs == "up" {
							ret_row["status_num"] = 1
						} else if vs == "down" {
							ret_row["status_num"] = 0
						} else {
							i, err := strconv.ParseInt(vs, 10, 64)
							if err == nil {
								ret_row["status_num"] = i
							}
						}
						continue
					}
					// everything is returned as text, so try to convert all numerics into ints / floats
					if k != "lb_weight" {
						i, err := strconv.ParseInt(vs, 10, 64)
						if err == nil {
							ret_row[k] = i
							continue
						}
					}
					f, err := strconv.ParseFloat(vs, 64)
					if err == nil {
						ret_row[k] = f
						continue
					}
				}
				ret_data = append(ret_data, ret_row)
			}
		} else if strings.HasPrefix(sql, "SHOW POOL_PROCESSES") {
			if len(ret_data) == 0 {
				log.Warningf("[%s][%s] SHOW POOL_NODES needs to be placed before SHOW POOL_PROCESSES. ignoring SHOW POOL_PROCESSES", msg.DBUniqueName, msg.MetricName)
				continue
			}

			data, err, dur := DBExecReadByDbUniqueName(msg.DBUniqueName, msg.MetricName, 0, sql)
			duration = duration + dur
			if err != nil {
				log.Errorf("[%s][%s] Could not fetch PgPool statistics: %v", msg.DBUniqueName, msg.MetricName, err)
				continue
			}

			// summarize processes_total / processes_active over all rows
			processes_total := 0
			processes_active := 0
			for _, row := range data {
				processes_total++
				v, ok := row["database"]
				if !ok {
					log.Infof("[%s][%s] column 'database' not found from data returned by SHOW POOL_PROCESSES, check pool version / SQL definition", msg.DBUniqueName, msg.MetricName)
					continue
				}
				if len(v.([]byte)) > 0 {
					processes_active++
				}
			}

			for _, ret_row := range ret_data {
				ret_row["processes_total"] = processes_total
				ret_row["processes_active"] = processes_active
			}
		}
	}

	//log.Fatalf("%+v", ret_data)
	return ret_data, nil, duration
}

func FetchMetrics(msg MetricFetchMessage, host_state map[string]map[string]string, storage_ch chan<- []MetricStoreMessage, context string) ([]MetricStoreMessage, error) {
	var vme DBVersionMapEntry
	var db_pg_version decimal.Decimal
	var err, firstErr error
	var sql string
	var retryWithSuperuserSQL = true
	var data, cachedData []map[string]interface{}
	var duration time.Duration
	var md MonitoredDatabase
	var fromCache, isCacheable bool

	vme, err = DBGetPGVersion(msg.DBUniqueName, msg.DBType, false)
	if err != nil {
		log.Error("failed to fetch pg version for ", msg.DBUniqueName, msg.MetricName, err)
		return nil, err
	}
	if msg.MetricName == SPECIAL_METRIC_DB_SIZE || msg.MetricName == SPECIAL_METRIC_TABLE_STATS {
		if vme.ExecEnv == EXEC_ENV_AZURE_SINGLE && vme.ApproxDBSizeB > 1e12 { // 1TB
			subsMetricName := msg.MetricName + "_approx"
			mvp_approx, err := GetMetricVersionProperties(subsMetricName, vme, nil)
			if err == nil && mvp_approx.MetricAttrs.MetricStorageName == msg.MetricName {
				log.Infof("[%s:%s] Transparently swapping metric to %s due to hard-coded rules...", msg.DBUniqueName, msg.MetricName, subsMetricName)
				msg.MetricName = subsMetricName
			}
		}
	}
	db_pg_version = vme.Version

	if msg.DBType == DBTYPE_BOUNCER {
		db_pg_version = decimal.Decimal{} // version is 0.0 for all pgbouncer sql per convention
	}

	mvp, err := GetMetricVersionProperties(msg.MetricName, vme, nil)
	if err != nil && msg.MetricName != RECO_METRIC_NAME {
		epoch, ok := last_sql_fetch_error.Load(msg.MetricName + DB_METRIC_JOIN_STR + db_pg_version.String())
		if !ok || ((time.Now().Unix() - epoch.(int64)) > 3600) { // complain only 1x per hour
			log.Infof("Failed to get SQL for metric '%s', version '%s': %v", msg.MetricName, vme.VersionStr, err)
			last_sql_fetch_error.Store(msg.MetricName+DB_METRIC_JOIN_STR+db_pg_version.String(), time.Now().Unix())
		}
		if strings.Contains(err.Error(), "too old") {
			return nil, nil
		}
		return nil, err
	}

	isCacheable = IsCacheableMetric(msg, mvp)
	if isCacheable && opts.InstanceLevelCacheMaxSeconds > 0 && msg.Interval.Seconds() > float64(opts.InstanceLevelCacheMaxSeconds) {
		cachedData = GetFromInstanceCacheIfNotOlderThanSeconds(msg, opts.InstanceLevelCacheMaxSeconds)
		if len(cachedData) > 0 {
			fromCache = true
			goto send_to_storage_channel
		}
	}

retry_with_superuser_sql: // if 1st fetch with normal SQL fails, try with SU SQL if it's defined

	sql = mvp.Sql

	if noHelperFunctions && mvp.CallsHelperFunctions && mvp.SqlSU != "" {
		log.Debugf("[%s:%s] Using SU SQL instead of normal one due to --no-helper-functions input", msg.DBUniqueName, msg.MetricName)
		sql = mvp.SqlSU
		retryWithSuperuserSQL = false
	}

	if (vme.IsSuperuser || (retryWithSuperuserSQL && firstErr != nil)) && mvp.SqlSU != "" {
		sql = mvp.SqlSU
		retryWithSuperuserSQL = false
	}
	if sql == "" && !(msg.MetricName == SPECIAL_METRIC_CHANGE_EVENTS || msg.MetricName == RECO_METRIC_NAME) {
		// let's ignore dummy SQL-s
		log.Debugf("[%s:%s] Ignoring fetch message - got an empty/dummy SQL string", msg.DBUniqueName, msg.MetricName)
		return nil, nil
	}

	if (mvp.MasterOnly && vme.IsInRecovery) || (mvp.StandbyOnly && !vme.IsInRecovery) {
		log.Debugf("[%s:%s] Skipping fetching of  as server not in wanted state (IsInRecovery=%v)", msg.DBUniqueName, msg.MetricName, vme.IsInRecovery)
		return nil, nil
	}

	if msg.MetricName == SPECIAL_METRIC_CHANGE_EVENTS && context != CONTEXT_PROMETHEUS_SCRAPE { // special handling, multiple queries + stateful
		CheckForPGObjectChangesAndStore(msg.DBUniqueName, vme, storage_ch, host_state) // TODO no host_state for Prometheus currently
	} else if msg.MetricName == RECO_METRIC_NAME && context != CONTEXT_PROMETHEUS_SCRAPE {
		data, _, duration = GetRecommendations(msg.DBUniqueName, vme)
	} else if msg.DBType == DBTYPE_PGPOOL {
		data, _, duration = FetchMetricsPgpool(msg, vme, mvp)
	} else {
		data, err, duration = DBExecReadByDbUniqueName(msg.DBUniqueName, msg.MetricName, mvp.MetricAttrs.StatementTimeoutSeconds, sql)

		if err != nil {
			// let's soften errors to "info" from functions that expect the server to be a primary to reduce noise
			if strings.Contains(err.Error(), "recovery is in progress") {
				db_pg_version_map_lock.RLock()
				ver := db_pg_version_map[msg.DBUniqueName]
				db_pg_version_map_lock.RUnlock()
				if ver.IsInRecovery {
					log.Debugf("[%s:%s] failed to fetch metrics: %s", msg.DBUniqueName, msg.MetricName, err)
					return nil, err
				}
			}

			if msg.MetricName == SPECIAL_METRIC_INSTANCE_UP {
				log.Debugf("[%s:%s] failed to fetch metrics. marking instance as not up: %s", msg.DBUniqueName, msg.MetricName, err)
				data = make([]map[string]interface{}, 1)
				data[0] = map[string]interface{}{"epoch_ns": time.Now().UnixNano(), "is_up": 0} // NB! should be updated if the "instance_up" metric definition is changed
				goto send_to_storage_channel
			}

			if strings.Contains(err.Error(), "connection refused") {
				SetDBUnreachableState(msg.DBUniqueName)
			}

			if retryWithSuperuserSQL && mvp.SqlSU != "" {
				firstErr = err
				log.Infof("[%s:%s] Normal fetch failed, re-trying to fetch with SU SQL", msg.DBUniqueName, msg.MetricName)
				goto retry_with_superuser_sql
			} else {
				if firstErr != nil {
					log.Infof("[%s:%s] failed to fetch metrics also with SU SQL so initial error will be returned. Current err: %s", msg.DBUniqueName, msg.MetricName, err)
					return nil, firstErr // returning the initial error
				} else {
					log.Infof("[%s:%s] failed to fetch metrics: %s", msg.DBUniqueName, msg.MetricName, err)
				}
			}
			return nil, err
		} else {
			md, err = GetMonitoredDatabaseByUniqueName(msg.DBUniqueName)
			if err != nil {
				log.Errorf("[%s:%s] could not get monitored DB details", msg.DBUniqueName, err)
				return nil, err
			}

			log.Infof("[%s:%s] fetched %d rows in %.1f ms", msg.DBUniqueName, msg.MetricName, len(data), float64(duration.Nanoseconds())/1000000)
			if regexIsPgbouncerMetrics.MatchString(msg.MetricName) { // clean unwanted pgbouncer pool stats here as not possible in SQL
				data = FilterPgbouncerData(data, md.DBName, vme)
			}

			ClearDBUnreachableStateIfAny(msg.DBUniqueName)
		}
	}

	if isCacheable && opts.InstanceLevelCacheMaxSeconds > 0 && msg.Interval.Seconds() > float64(opts.InstanceLevelCacheMaxSeconds) {
		PutToInstanceCache(msg, data)
	}

send_to_storage_channel:

	if (addRealDbname || addSystemIdentifier) && msg.DBType == DBTYPE_PG {
		db_pg_version_map_lock.RLock()
		ver := db_pg_version_map[msg.DBUniqueName]
		db_pg_version_map_lock.RUnlock()
		data = AddDbnameSysinfoIfNotExistsToQueryResultData(msg, data, ver)
	}

	if mvp.MetricAttrs.MetricStorageName != "" {
		log.Debugf("[%s] rerouting metric %s data to %s based on metric attributes", msg.DBUniqueName, msg.MetricName, mvp.MetricAttrs.MetricStorageName)
		msg.MetricName = mvp.MetricAttrs.MetricStorageName
	}
	if fromCache {
		md, err = GetMonitoredDatabaseByUniqueName(msg.DBUniqueName)
		if err != nil {
			log.Errorf("[%s:%s] could not get monitored DB details", msg.DBUniqueName, err)
			return nil, err
		}
		log.Infof("[%s:%s] loaded %d rows from the instance cache", msg.DBUniqueName, msg.MetricName, len(cachedData))
		atomic.AddUint64(&totalMetricsReusedFromCacheCounter, uint64(len(cachedData)))
		return []MetricStoreMessage{MetricStoreMessage{DBUniqueName: msg.DBUniqueName, MetricName: msg.MetricName, Data: cachedData, CustomTags: md.CustomTags,
			MetricDefinitionDetails: mvp, RealDbname: vme.RealDbname, SystemIdentifier: vme.SystemIdentifier}}, nil
	} else {
		atomic.AddUint64(&totalMetricsFetchedCounter, uint64(len(data)))
		return []MetricStoreMessage{MetricStoreMessage{DBUniqueName: msg.DBUniqueName, MetricName: msg.MetricName, Data: data, CustomTags: md.CustomTags,
			MetricDefinitionDetails: mvp, RealDbname: vme.RealDbname, SystemIdentifier: vme.SystemIdentifier}}, nil
	}
}

func SetDBUnreachableState(dbUnique string) {
	unreachableDBsLock.Lock()
	unreachableDB[dbUnique] = time.Now()
	unreachableDBsLock.Unlock()
}

func ClearDBUnreachableStateIfAny(dbUnique string) {
	unreachableDBsLock.Lock()
	delete(unreachableDB, dbUnique)
	unreachableDBsLock.Unlock()
}

func PurgeMetricsFromPromAsyncCacheIfAny(dbUnique, metric string) {
	if promAsyncMode {
		promAsyncMetricCacheLock.Lock()
		defer promAsyncMetricCacheLock.Unlock()

		if metric == "" {
			delete(promAsyncMetricCache, dbUnique) // whole host removed from config
		} else {
			delete(promAsyncMetricCache[dbUnique], metric)
		}
	}
}

func GetFromInstanceCacheIfNotOlderThanSeconds(msg MetricFetchMessage, maxAgeSeconds int64) []map[string]interface{} {
	var clonedData []map[string]interface{}
	instanceMetricCacheTimestampLock.RLock()
	instanceMetricTS, ok := instanceMetricCacheTimestamp[msg.DBUniqueNameOrig+msg.MetricName]
	instanceMetricCacheTimestampLock.RUnlock()
	if !ok {
		//log.Debugf("[%s:%s] no instance cache entry", msg.DBUniqueNameOrig, msg.MetricName)
		return nil
	}

	if time.Now().Unix()-instanceMetricTS.Unix() > maxAgeSeconds {
		//log.Debugf("[%s:%s] instance cache entry too old", msg.DBUniqueNameOrig, msg.MetricName)
		return nil
	}

	log.Debugf("[%s:%s] reading metric data from instance cache of \"%s\"", msg.DBUniqueName, msg.MetricName, msg.DBUniqueNameOrig)
	instanceMetricCacheLock.RLock()
	instanceMetricData, ok := instanceMetricCache[msg.DBUniqueNameOrig+msg.MetricName]
	if !ok {
		instanceMetricCacheLock.RUnlock()
		return nil
	}
	clonedData = deepCopyMetricData(instanceMetricData)
	instanceMetricCacheLock.RUnlock()

	return clonedData
}

func PutToInstanceCache(msg MetricFetchMessage, data []map[string]interface{}) {
	if len(data) == 0 {
		return
	}
	dataCopy := deepCopyMetricData(data)
	log.Debugf("[%s:%s] filling instance cache", msg.DBUniqueNameOrig, msg.MetricName)
	instanceMetricCacheLock.Lock()
	instanceMetricCache[msg.DBUniqueNameOrig+msg.MetricName] = dataCopy
	instanceMetricCacheLock.Unlock()

	instanceMetricCacheTimestampLock.Lock()
	instanceMetricCacheTimestamp[msg.DBUniqueNameOrig+msg.MetricName] = time.Now()
	instanceMetricCacheTimestampLock.Unlock()
}

func IsCacheableMetric(msg MetricFetchMessage, mvp MetricVersionProperties) bool {
	if !(msg.DBType == DBTYPE_PG_CONT || msg.DBType == DBTYPE_PATRONI_CONT) {
		return false
	}
	return mvp.MetricAttrs.IsInstanceLevel
}

func AddDbnameSysinfoIfNotExistsToQueryResultData(msg MetricFetchMessage, data []map[string]interface{}, ver DBVersionMapEntry) []map[string]interface{} {
	enriched_data := make([]map[string]interface{}, 0)

	log.Debugf("Enriching all rows of [%s:%s] with sysinfo (%s) / real dbname (%s) if set. ", msg.DBUniqueName, msg.MetricName, ver.SystemIdentifier, ver.RealDbname)
	for _, dr := range data {
		if addRealDbname && ver.RealDbname != "" {
			old, ok := dr[TAG_PREFIX+opts.RealDbnameField]
			if !ok || old == "" {
				dr[TAG_PREFIX+opts.RealDbnameField] = ver.RealDbname
			}
		}
		if addSystemIdentifier && ver.SystemIdentifier != "" {
			old, ok := dr[TAG_PREFIX+opts.SystemIdentifierField]
			if !ok || old == "" {
				dr[TAG_PREFIX+opts.SystemIdentifierField] = ver.SystemIdentifier
			}
		}
		enriched_data = append(enriched_data, dr)
	}
	return enriched_data
}

func StoreMetrics(metrics []MetricStoreMessage, storage_ch chan<- []MetricStoreMessage) (int, error) {

	if len(metrics) > 0 {
		atomic.AddUint64(&totalDatasetsFetchedCounter, 1)
		storage_ch <- metrics
		return len(metrics), nil
	}

	return 0, nil
}

func deepCopyMetricStoreMessages(metricStoreMessages []MetricStoreMessage) []MetricStoreMessage {
	new := make([]MetricStoreMessage, 0)
	for _, msm := range metricStoreMessages {
		data_new := make([]map[string]interface{}, 0)
		for _, dr := range msm.Data {
			dr_new := make(map[string]interface{})
			for k, v := range dr {
				dr_new[k] = v
			}
			data_new = append(data_new, dr_new)
		}
		tag_data_new := make(map[string]string)
		for k, v := range msm.CustomTags {
			tag_data_new[k] = v
		}

		m := MetricStoreMessage{DBUniqueName: msm.DBUniqueName, MetricName: msm.MetricName, DBType: msm.DBType,
			Data: data_new, CustomTags: tag_data_new}
		new = append(new, m)
	}
	return new
}

func deepCopyMetricData(data []map[string]interface{}) []map[string]interface{} {
	newData := make([]map[string]interface{}, len(data))

	for i, dr := range data {
		newRow := make(map[string]interface{})
		for k, v := range dr {
			newRow[k] = v
		}
		newData[i] = newRow
	}

	return newData
}

func deepCopyMetricDefinitionMap(mdm map[string]map[decimal.Decimal]MetricVersionProperties) map[string]map[decimal.Decimal]MetricVersionProperties {
	newMdm := make(map[string]map[decimal.Decimal]MetricVersionProperties)

	for metric, verMap := range mdm {
		newMdm[metric] = make(map[decimal.Decimal]MetricVersionProperties)
		for ver, mvp := range verMap {
			newMdm[metric][ver] = mvp
		}
	}
	return newMdm
}

// ControlMessage notifies of shutdown + interval change
func MetricGathererLoop(dbUniqueName, dbUniqueNameOrig, dbType, metricName string, config_map map[string]float64, control_ch <-chan ControlMessage, store_ch chan<- []MetricStoreMessage) {
	config := config_map
	interval := config[metricName]
	ticker := time.NewTicker(time.Millisecond * time.Duration(interval*1000))
	host_state := make(map[string]map[string]string)
	var last_uptime_s int64 = -1 // used for "server restarted" event detection
	var last_error_notification_time time.Time
	var vme DBVersionMapEntry
	var mvp MetricVersionProperties
	var err error
	failed_fetches := 0
	metricNameForStorage := metricName
	lastDBVersionFetchTime := time.Unix(0, 0) // check DB ver. ev. 5 min
	var stmtTimeoutOverride int64

	if opts.TestdataDays != 0 {
		if metricName == SPECIAL_METRIC_SERVER_LOG_EVENT_COUNTS || metricName == SPECIAL_METRIC_CHANGE_EVENTS {
			return
		}
		testDataGenerationModeWG.Add(1)
	}
	if opts.Datastore == DATASTORE_POSTGRES && opts.TestdataDays == 0 {
		if _, is_special_metric := specialMetrics[metricName]; !is_special_metric {
			vme, err := DBGetPGVersion(dbUniqueName, dbType, false)
			if err != nil {
				log.Warningf("[%s][%s] Failed to determine possible re-routing name, Grafana dashboards with re-routed metrics might not show all hosts", dbUniqueName, metricName)
			} else {
				mvp, err := GetMetricVersionProperties(metricName, vme, nil)
				if err != nil && !strings.Contains(err.Error(), "too old") {
					log.Warningf("[%s][%s] Failed to determine possible re-routing name, Grafana dashboards with re-routed metrics might not show all hosts", dbUniqueName, metricName)
				} else if mvp.MetricAttrs.MetricStorageName != "" {
					metricNameForStorage = mvp.MetricAttrs.MetricStorageName
				}
			}
		}

		err := AddDBUniqueMetricToListingTable(dbUniqueName, metricNameForStorage)
		if err != nil {
			log.Errorf("Could not add newly found gatherer [%s:%s] to the 'all_distinct_dbname_metrics' listing table: %v", dbUniqueName, metricName, err)
		}

		EnsureMetricDummy(metricNameForStorage) // ensure that there is at least an empty top-level table not to get ugly Grafana notifications
	}

	if metricName == SPECIAL_METRIC_SERVER_LOG_EVENT_COUNTS {
		logparseLoop(dbUniqueName, metricName, config_map, control_ch, store_ch) // no return
		return
	}

	for {
		if lastDBVersionFetchTime.Add(time.Minute * time.Duration(5)).Before(time.Now()) {
			vme, err = DBGetPGVersion(dbUniqueName, dbType, false) // in case of errors just ignore metric "disabled" time ranges
			if err != nil {
				lastDBVersionFetchTime = time.Now()
			}

			mvp, err = GetMetricVersionProperties(metricName, vme, nil)
			if err == nil && mvp.MetricAttrs.StatementTimeoutSeconds > 0 {
				stmtTimeoutOverride = mvp.MetricAttrs.StatementTimeoutSeconds
			} else {
				stmtTimeoutOverride = 0
			}
		}

		metricCurrentlyDisabled := IsMetricCurrentlyDisabledForHost(metricName, vme, dbUniqueName)
		if metricCurrentlyDisabled && opts.TestdataDays == 0 {
			log.Debugf("[%s][%s] Ignoring fetch as metric disabled for current time range", dbUniqueName, metricName)
		} else {
			var metricStoreMessages []MetricStoreMessage
			var err error
			mfm := MetricFetchMessage{DBUniqueName: dbUniqueName, DBUniqueNameOrig: dbUniqueNameOrig, MetricName: metricName, DBType: dbType, Interval: time.Second * time.Duration(interval), StmtTimeoutOverride: stmtTimeoutOverride}

			// 1st try local overrides for some metrics if operating in push mode
			if tryDirectOSStats && IsDirectlyFetchableMetric(metricName) {
				metricStoreMessages, err = FetchStatsDirectlyFromOS(mfm, vme, mvp)
				if err != nil {
					log.Errorf("[%s][%s] Could not reader metric directly from OS: %v", dbUniqueName, metricName, err)
				}
			}
			t1 := time.Now()
			if metricStoreMessages == nil {
				metricStoreMessages, err = FetchMetrics(
					mfm,
					host_state,
					store_ch,
					"")
			}
			t2 := time.Now()

			if t2.Sub(t1) > (time.Second * time.Duration(interval)) {
				log.Warningf("Total fetching time of %vs bigger than %vs interval for [%s:%s]", t2.Sub(t1).Truncate(time.Millisecond*100).Seconds(), interval, dbUniqueName, metricName)
			}

			if err != nil {
				failed_fetches += 1
				// complain only 1x per 10min per host/metric...
				if last_error_notification_time.IsZero() || last_error_notification_time.Add(time.Second*time.Duration(600)).Before(time.Now()) {
					log.Errorf("Failed to fetch metric data for [%s:%s]: %v", dbUniqueName, metricName, err)
					if failed_fetches > 1 {
						log.Errorf("Total failed fetches for [%s:%s]: %d", dbUniqueName, metricName, failed_fetches)
					}
					last_error_notification_time = time.Now()
				}
			} else if metricStoreMessages != nil {
				if opts.Datastore == DATASTORE_PROMETHEUS && promAsyncMode && len(metricStoreMessages[0].Data) == 0 {
					PurgeMetricsFromPromAsyncCacheIfAny(dbUniqueName, metricName)
				}
				if len(metricStoreMessages[0].Data) > 0 {

					// pick up "server restarted" events here to avoid doing extra selects from CheckForPGObjectChangesAndStore code
					if metricName == "db_stats" {
						postmaster_uptime_s, ok := (metricStoreMessages[0].Data)[0]["postmaster_uptime_s"]
						if ok {
							if last_uptime_s != -1 {
								if postmaster_uptime_s.(int64) < last_uptime_s { // restart (or possibly also failover when host is routed) happened
									message := "Detected server restart (or failover) of \"" + dbUniqueName + "\""
									log.Warning(message)
									detected_changes_summary := make([](map[string]interface{}), 0)
									entry := map[string]interface{}{"details": message, "epoch_ns": (metricStoreMessages[0].Data)[0]["epoch_ns"]}
									detected_changes_summary = append(detected_changes_summary, entry)
									metricStoreMessages = append(metricStoreMessages,
										MetricStoreMessage{DBUniqueName: dbUniqueName, DBType: dbType,
											MetricName: "object_changes", Data: detected_changes_summary, CustomTags: metricStoreMessages[0].CustomTags})
								}
							}
							last_uptime_s = postmaster_uptime_s.(int64)
						}
					}

					if opts.TestdataDays != 0 {
						orig_msms := deepCopyMetricStoreMessages(metricStoreMessages)
						log.Warningf("Generating %d days of data for [%s:%s]", opts.TestdataDays, dbUniqueName, metricName)
						test_metrics_stored := 0
						simulated_time := t1
						end_time := t1.Add(time.Hour * time.Duration(opts.TestdataDays*24))

						if opts.TestdataDays < 0 {
							simulated_time, end_time = end_time, simulated_time
						}

						for simulated_time.Before(end_time) {
							log.Debugf("Metric [%s], simulating time: %v", metricName, simulated_time)
							for host_nr := 1; host_nr <= opts.TestdataMultiplier; host_nr++ {
								fake_dbname := fmt.Sprintf("%s-%d", dbUniqueName, host_nr)
								msgs_copy_tmp := deepCopyMetricStoreMessages(orig_msms)

								for i := 0; i < len(msgs_copy_tmp[0].Data); i++ {
									(msgs_copy_tmp[0].Data)[i][EPOCH_COLUMN_NAME] = (simulated_time.UnixNano() + int64(1000*i))
								}
								msgs_copy_tmp[0].DBUniqueName = fake_dbname
								//log.Debugf("fake data for [%s:%s]: %v", metricName, fake_dbname, msgs_copy_tmp[0].Data)
								_, _ = StoreMetrics(msgs_copy_tmp, store_ch)
								test_metrics_stored += len(msgs_copy_tmp[0].Data)
							}
							time.Sleep(time.Duration(opts.TestdataMultiplier * 10000000)) // 10ms * multiplier (in nanosec).
							// would generate more metrics than persister can write and eat up RAM
							simulated_time = simulated_time.Add(time.Second * time.Duration(interval))
						}
						log.Warningf("exiting MetricGathererLoop for [%s], %d total data points generated for %d hosts",
							metricName, test_metrics_stored, opts.TestdataMultiplier)
						testDataGenerationModeWG.Done()
						return
					} else {
						_, _ = StoreMetrics(metricStoreMessages, store_ch)
					}
				}
			}

			if opts.TestdataDays != 0 { // covers errors & no data
				testDataGenerationModeWG.Done()
				return
			}

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

func FetchStatsDirectlyFromOS(msg MetricFetchMessage, vme DBVersionMapEntry, mvp MetricVersionProperties) ([]MetricStoreMessage, error) {
	var data []map[string]interface{}
	var err error

	if msg.MetricName == METRIC_CPU_LOAD { // could function pointers work here?
		data, err = GetLoadAvgLocal()
	} else if msg.MetricName == METRIC_PSUTIL_CPU {
		data, err = GetGoPsutilCPU(msg.Interval)
	} else if msg.MetricName == METRIC_PSUTIL_DISK {
		data, err = GetGoPsutilDiskPG(msg.DBUniqueName)
	} else if msg.MetricName == METRIC_PSUTIL_DISK_IO_TOTAL {
		data, err = GetGoPsutilDiskTotals()
	} else if msg.MetricName == METRIC_PSUTIL_MEM {
		data, err = GetGoPsutilMem()
	}
	if err != nil {
		return nil, err
	}

	msm := DatarowsToMetricstoreMessage(data, msg, vme, mvp)
	return []MetricStoreMessage{msm}, nil
}

// data + custom tags + counters
func DatarowsToMetricstoreMessage(data []map[string]interface{}, msg MetricFetchMessage, vme DBVersionMapEntry, mvp MetricVersionProperties) MetricStoreMessage {
	md, err := GetMonitoredDatabaseByUniqueName(msg.DBUniqueName)
	if err != nil {
		log.Errorf("Could not resolve DBUniqueName %s, cannot set custom attributes for gathered data: %v", msg.DBUniqueName, err)
	}

	atomic.AddUint64(&totalMetricsFetchedCounter, uint64(len(data)))

	return MetricStoreMessage{
		DBUniqueName:            msg.DBUniqueName,
		DBType:                  msg.DBType,
		MetricName:              msg.MetricName,
		CustomTags:              md.CustomTags,
		Data:                    data,
		MetricDefinitionDetails: mvp,
		RealDbname:              vme.RealDbname,
		SystemIdentifier:        vme.SystemIdentifier,
	}
}

func IsDirectlyFetchableMetric(metric string) bool {
	if _, ok := directlyFetchableOSMetrics[metric]; ok {
		return true
	}
	return false
}

func IsStringInSlice(target string, slice []string) bool {
	for _, s := range slice {
		if target == s {
			return true
		}
	}
	return false
}

func IsMetricCurrentlyDisabledForHost(metricName string, vme DBVersionMapEntry, dbUniqueName string) bool {
	_, isSpecialMetric := specialMetrics[metricName]

	mvp, err := GetMetricVersionProperties(metricName, vme, nil)
	if err != nil {
		if isSpecialMetric || strings.Contains(err.Error(), "too old") {
			return false
		}
		log.Warningf("[%s][%s] Ignoring any possible time based gathering restrictions, could not get metric details", dbUniqueName, metricName)
		return false
	}

	md, err := GetMonitoredDatabaseByUniqueName(dbUniqueName) // TODO caching?
	if err != nil {
		log.Warningf("[%s][%s] Ignoring any possible time based gathering restrictions, could not get DB details", dbUniqueName, metricName)
		return false
	}

	if md.HostConfig.PerMetricDisabledTimes == nil && mvp.MetricAttrs.DisabledDays == "" && len(mvp.MetricAttrs.DisableTimes) == 0 {
		//log.Debugf("[%s][%s] No time based gathering restrictions defined", dbUniqueName, metricName)
		return false
	}

	metricHasOverrides := false
	if md.HostConfig.PerMetricDisabledTimes != nil {
		for _, hcdt := range md.HostConfig.PerMetricDisabledTimes {
			if IsStringInSlice(metricName, hcdt.Metrics) && (hcdt.DisabledDays != "" || len(hcdt.DisabledTimes) > 0) {
				metricHasOverrides = true
				break
			}
		}
		if !metricHasOverrides && mvp.MetricAttrs.DisabledDays == "" && len(mvp.MetricAttrs.DisableTimes) == 0 {
			//log.Debugf("[%s][%s] No time based gathering restrictions defined", dbUniqueName, metricName)
			return false
		}
	}

	return IsInDisabledTimeDayRange(time.Now(), mvp.MetricAttrs.DisabledDays, mvp.MetricAttrs.DisableTimes, md.HostConfig.PerMetricDisabledTimes, metricName, dbUniqueName)
}

// days: 0 = Sun, ranges allowed
func IsInDaySpan(locTime time.Time, days, metric, dbUnique string) bool {
	//log.Debug("IsInDaySpan", locTime, days, metric, dbUnique)
	if days == "" {
		return false
	}
	curDayInt := int(locTime.Weekday())
	daysMap := DaysStringToIntMap(days)
	//log.Debugf("curDayInt %v, daysMap %+v", curDayInt, daysMap)
	_, ok := daysMap[curDayInt]
	return ok
}

func DaysStringToIntMap(days string) map[int]bool { // TODO validate with some regex when reading in configs, have dbname info then
	ret := make(map[int]bool)
	for _, s := range strings.Split(days, ",") {
		if strings.Contains(s, "-") {
			dayRange := strings.Split(s, "-")
			if len(dayRange) != 2 {
				log.Warningf("Ignoring invalid day range specification: %s. Check config", s)
				continue
			}
			startDay, err := strconv.Atoi(dayRange[0])
			endDay, err2 := strconv.Atoi(dayRange[1])
			if err != nil || err2 != nil {
				log.Warningf("Ignoring invalid day range specification: %s. Check config", s)
				continue
			}
			for i := startDay; i <= endDay && i >= 0 && i <= 7; i++ {
				ret[i] = true
			}

		} else {
			day, err := strconv.Atoi(s)
			if err != nil {
				log.Warningf("Ignoring invalid day range specification: %s. Check config", days)
				continue
			}
			ret[day] = true
		}
	}
	if _, ok := ret[7]; ok { // Cron allows either 0 or 7 for Sunday
		ret[0] = true
	}
	return ret
}

func IsInTimeSpan(checkTime time.Time, timeRange, metric, dbUnique string) bool {
	layout := "15:04"
	var t1, t2 time.Time
	var err error

	timeRange = strings.TrimSpace(timeRange)
	if len(timeRange) < 11 {
		log.Warningf("[%s][%s] invalid time range: %s. Check config", dbUnique, metric, timeRange)
		return false
	}
	s1 := timeRange[0:5]
	s2 := timeRange[6:11]
	tz := strings.TrimSpace(timeRange[11:])

	if len(tz) > 1 { // time zone specified
		if regexIsAlpha.MatchString(tz) {
			layout = "15:04 MST"
		} else {
			layout = "15:04 -0700"
		}
		t1, err = time.Parse(layout, s1+" "+tz)
		if err == nil {
			t2, err = time.Parse(layout, s2+" "+tz)
		}
	} else { // no time zone
		t1, err = time.Parse(layout, s1)
		if err == nil {
			t2, err = time.Parse(layout, s2)
		}
	}

	if err != nil {
		log.Warningf("[%s][%s] Ignoring invalid disabled time range: %s. Check config. Erorr: %v", dbUnique, metric, timeRange, err)
		return false
	}

	check, err := time.Parse("15:04 -0700", strconv.Itoa(checkTime.Hour())+":"+strconv.Itoa(checkTime.Minute())+" "+t1.Format("-0700")) // UTC by default
	if err != nil {
		log.Warningf("[%s][%s] Ignoring invalid disabled time range: %s. Check config. Error: %v", dbUnique, metric, timeRange, err)
		return false
	}

	if t1.After(t2) {
		t2 = t2.AddDate(0, 0, 1)
	}

	return check.Before(t2) && check.After(t1)
}

func IsInDisabledTimeDayRange(localTime time.Time, metricAttrsDisabledDays string, metricAttrsDisabledTimes []string, hostConfigPerMetricDisabledTimes []HostConfigPerMetricDisabledTimes, metric, dbUnique string) bool {
	hostConfigMetricMatch := false
	for _, hcdi := range hostConfigPerMetricDisabledTimes { // host config takes precedence when both specified
		dayMatchFound := false
		timeMatchFound := false
		if IsStringInSlice(metric, hcdi.Metrics) {
			hostConfigMetricMatch = true
			if !dayMatchFound && hcdi.DisabledDays != "" && IsInDaySpan(localTime, hcdi.DisabledDays, metric, dbUnique) {
				dayMatchFound = true
			}
			for _, dt := range hcdi.DisabledTimes {
				if IsInTimeSpan(localTime, dt, metric, dbUnique) {
					timeMatchFound = true
					break
				}
			}
		}
		if hostConfigMetricMatch && (timeMatchFound || len(hcdi.DisabledTimes) == 0) && (dayMatchFound || hcdi.DisabledDays == "") {
			//log.Debugf("[%s][%s] Host config ignored time/day match, skipping fetch", dbUnique, metric)
			return true
		}
	}

	if !hostConfigMetricMatch && (metricAttrsDisabledDays != "" || len(metricAttrsDisabledTimes) > 0) {
		dayMatchFound := IsInDaySpan(localTime, metricAttrsDisabledDays, metric, dbUnique)
		timeMatchFound := false
		for _, timeRange := range metricAttrsDisabledTimes {
			if IsInTimeSpan(localTime, timeRange, metric, dbUnique) {
				timeMatchFound = true
				break
			}
		}
		if (timeMatchFound || len(metricAttrsDisabledTimes) == 0) && (dayMatchFound || metricAttrsDisabledDays == "") {
			//log.Debugf("[%s][%s] MetricAttrs ignored time/day match, skipping fetch", dbUnique, metric)
			return true
		}
	}

	return false
}

func UpdateMetricDefinitionMap(newMetrics map[string]map[decimal.Decimal]MetricVersionProperties) {
	metric_def_map_lock.Lock()
	metric_def_map = newMetrics
	metric_def_map_lock.Unlock()
	//log.Debug("metric_def_map:", metric_def_map)
	log.Debug("metrics definitions refreshed - nr. found:", len(newMetrics))
}

func ReadMetricDefinitionMapFromPostgres(failOnError bool) (map[string]map[decimal.Decimal]MetricVersionProperties, error) {
	metric_def_map_new := make(map[string]map[decimal.Decimal]MetricVersionProperties)
	metricNameRemapsNew := make(map[string]string)
	sql := `select /* pgwatch2_generated */ m_name, m_pg_version_from::text, m_sql, m_master_only, m_standby_only,
			  coalesce(m_column_attrs::text, '') as m_column_attrs, coalesce(m_column_attrs::text, '') as m_column_attrs,
			  coalesce(ma_metric_attrs::text, '') as ma_metric_attrs, m_sql_su
			from
              pgwatch2.metric
              left join
              pgwatch2.metric_attribute on (ma_metric_name = m_name)
			where
              m_is_active
		    order by
		      1, 2`

	log.Info("updating metrics definitons from ConfigDB...")
	data, err := DBExecRead(configDb, CONFIGDB_IDENT, sql)
	if err != nil {
		if failOnError {
			log.Fatal(err)
		} else {
			log.Error(err)
			return metric_def_map, err
		}
	}
	if len(data) == 0 {
		log.Warning("no active metric definitions found from config DB")
		return metric_def_map_new, err
	}

	log.Debug(len(data), "active metrics found from config db (pgwatch2.metric)")
	for _, row := range data {
		_, ok := metric_def_map_new[row["m_name"].(string)]
		if !ok {
			metric_def_map_new[row["m_name"].(string)] = make(map[decimal.Decimal]MetricVersionProperties)
		}
		d, _ := decimal.NewFromString(row["m_pg_version_from"].(string))
		ca := MetricColumnAttrs{}
		if row["m_column_attrs"].(string) != "" {
			ca = ParseMetricColumnAttrsFromString(row["m_column_attrs"].(string))
		}
		ma := MetricAttrs{}
		if row["ma_metric_attrs"].(string) != "" {
			ma = ParseMetricAttrsFromString(row["ma_metric_attrs"].(string))
			if ma.MetricStorageName != "" {
				metricNameRemapsNew[row["m_name"].(string)] = ma.MetricStorageName
			}
		}
		metric_def_map_new[row["m_name"].(string)][d] = MetricVersionProperties{
			Sql:                  row["m_sql"].(string),
			SqlSU:                row["m_sql_su"].(string),
			MasterOnly:           row["m_master_only"].(bool),
			StandbyOnly:          row["m_standby_only"].(bool),
			ColumnAttrs:          ca,
			MetricAttrs:          ma,
			CallsHelperFunctions: DoesMetricDefinitionCallHelperFunctions(row["m_sql"].(string)),
		}
	}

	metricNameRemapLock.Lock()
	metricNameRemaps = metricNameRemapsNew
	metricNameRemapLock.Unlock()

	return metric_def_map_new, err
}

func jsonTextToMap(jsonText string) (map[string]float64, error) {
	retmap := make(map[string]float64)
	if jsonText == "" {
		return retmap, nil
	}
	var host_config map[string]interface{}
	if err := json.Unmarshal([]byte(jsonText), &host_config); err != nil {
		return nil, err
	}
	for k, v := range host_config {
		retmap[k] = v.(float64)
	}
	return retmap, nil
}

func jsonTextToStringMap(jsonText string) (map[string]string, error) {
	retmap := make(map[string]string)
	if jsonText == "" {
		return retmap, nil
	}
	var iMap map[string]interface{}
	if err := json.Unmarshal([]byte(jsonText), &iMap); err != nil {
		return nil, err
	}
	for k, v := range iMap {
		retmap[k] = fmt.Sprintf("%v", v)
	}
	return retmap, nil
}

func mapToJson(metricsMap map[string]interface{}) ([]byte, error) {
	return json.Marshal(metricsMap)
}

// queryInfluxDB convenience function to query the database
func queryInfluxDB(clnt client.Client, cmd string) (res []client.Result, err error) {
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
	var pgwatchDbExists bool = false
	skipSSLCertVerify, _ := strconv.ParseBool(SkipSSLCertVerify)
	retries := 3

	if b, _ := strconv.ParseBool(InfluxSSL); b {
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

retry:
	res, err := queryInfluxDB(c, "SHOW DATABASES")

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
			pgwatchDbExists = true
			break
		}
	}
	if pgwatchDbExists && RetentionPeriod > 0 {
		var currentRetentionAsString string
		// get current retention period
		res, err := queryInfluxDB(c, fmt.Sprintf("SHOW RETENTION POLICIES ON %s", InfluxDbname))
		if err != nil {
			log.Errorf("Could not check Influx retention policies: %v", err)
			return connect_string, err
		}
		for _, rp := range res[0].Series[0].Values {
			log.Debugf("Found retention policy: %+v", rp)
			if opts.InfluxRetentionName == rp[0].(string) {
				// duration is represented as "720h0m0s" so construct similar string from --iretentiondays input
				currentRetentionAsString = rp[1].(string)
				break
			}
		}
		targetRetentionAsString := fmt.Sprintf("%dh0m0s", RetentionPeriod*24)
		if currentRetentionAsString != targetRetentionAsString {
			log.Warningf("InfluxDB retention policy change detected, changing from %s to %s ...", currentRetentionAsString, targetRetentionAsString)
			isql := fmt.Sprintf("ALTER RETENTION POLICY %s ON %s DURATION %dd REPLICATION 1 SHARD DURATION 1d", opts.InfluxRetentionName, InfluxDbname, RetentionPeriod)
			log.Warningf("Executing: %s", isql)
			_, err = queryInfluxDB(c, isql)
			if err != nil {
				log.Errorf("Could not change InfluxDB retention policy - manul review / correction recommended: %v", err)
			}
		}
		return connect_string, nil
	} else if !pgwatchDbExists {
		log.Warningf("Database '%s' not found! Creating with %d days retention and retention policy name \"%s\"...", InfluxDbname, RetentionPeriod, opts.InfluxRetentionName)
		isql := fmt.Sprintf("CREATE DATABASE %s WITH DURATION %dd REPLICATION 1 SHARD DURATION 1d NAME %s", InfluxDbname, RetentionPeriod, opts.InfluxRetentionName)
		_, err = queryInfluxDB(c, isql)
		if err != nil {
			log.Fatal(err)
		} else {
			log.Infof("Database 'pgwatch2' created on InfluxDB host %s:%s", InfluxHost, InfluxPort)
		}
	}

	return connect_string, nil
}

func DoesFunctionExists(dbUnique, functionName string) bool {
	log.Debug("Checking for function existence", dbUnique, functionName)
	sql := fmt.Sprintf("select /* pgwatch2_generated */ 1 from pg_proc join pg_namespace n on pronamespace = n.oid where proname = '%s' and n.nspname = 'public'", functionName)
	data, err, _ := DBExecReadByDbUniqueName(dbUnique, "", 0, sql)
	if err != nil {
		log.Error("Failed to check for function existence", dbUnique, functionName, err)
		return false
	}
	if len(data) > 0 {
		log.Debugf("Function %s exists on %s", functionName, dbUnique)
		return true
	}
	return false
}

// Called once on daemon startup if some commonly wanted extension (most notably pg_stat_statements) is missing.
// NB! With newer Postgres version can even succeed if the user is not a real superuser due to some cloud-specific
// whitelisting or "trusted extensions" (a feature from v13). Ignores errors.
func TryCreateMissingExtensions(dbUnique string, extensionNames []string, existingExtensions map[string]decimal.Decimal) []string {
	sqlAvailable := `select name::text from pg_available_extensions`
	extsCreated := make([]string, 0)

	// For security reasons don't allow to execute random strings but check that it's an existing extension
	data, err, _ := DBExecReadByDbUniqueName(dbUnique, "", 0, sqlAvailable)
	if err != nil {
		log.Infof("[%s] Failed to get a list of available extensions: %v", dbUnique, err)
		return extsCreated
	}

	availableExts := make(map[string]bool)
	for _, row := range data {
		availableExts[row["name"].(string)] = true
	}

	for _, extToCreate := range extensionNames {
		if _, ok := existingExtensions[extToCreate]; ok {
			continue
		}
		_, ok := availableExts[extToCreate]
		if !ok {
			log.Errorf("[%s] Requested extension %s not available on instance, cannot try to create...", dbUnique, extToCreate)
		} else {
			sqlCreateExt := `create extension ` + extToCreate
			_, err, _ := DBExecReadByDbUniqueName(dbUnique, "", 0, sqlCreateExt)
			if err != nil {
				log.Errorf("[%s] Failed to create extension %s (based on --try-create-listed-exts-if-missing input): %v", dbUnique, extToCreate, err)
			}
			extsCreated = append(extsCreated, extToCreate)
		}
	}

	return extsCreated
}

// Called once on daemon startup to try to create "metric fething helper" functions automatically
func TryCreateMetricsFetchingHelpers(dbUnique string) error {
	db_pg_version, err := DBGetPGVersion(dbUnique, DBTYPE_PG, false)
	if err != nil {
		log.Errorf("Failed to fetch pg version for \"%s\": %s", dbUnique, err)
		return err
	}

	if fileBasedMetrics {
		helpers, err := ReadMetricsFromFolder(path.Join(opts.MetricsFolder, FILE_BASED_METRIC_HELPERS_DIR), false)
		if err != nil {
			log.Errorf("Failed to fetch helpers from \"%s\": %s", path.Join(opts.MetricsFolder, FILE_BASED_METRIC_HELPERS_DIR), err)
			return err
		}
		log.Debug("%d helper definitions found from \"%s\"...", len(helpers), path.Join(opts.MetricsFolder, FILE_BASED_METRIC_HELPERS_DIR))

		for helperName := range helpers {
			if strings.Contains(helperName, "windows") {
				log.Infof("Skipping %s rollout. Windows helpers need to be rolled out manually", helperName)
				continue
			}
			if !DoesFunctionExists(dbUnique, helperName) {

				log.Debug("Trying to create metric fetching helpers for", dbUnique, helperName)
				mvp, err := GetMetricVersionProperties(helperName, db_pg_version, helpers)
				if err != nil {
					log.Warning("Could not find query text for", dbUnique, helperName)
					continue
				}
				_, err, _ = DBExecReadByDbUniqueName(dbUnique, "", 0, mvp.Sql)
				if err != nil {
					log.Warning("Failed to create a metric fetching helper for", dbUnique, helperName)
					log.Warning(err)
				} else {
					log.Info("Successfully created metric fetching helper for", dbUnique, helperName)
				}
			}
		}

	} else {
		sql_helpers := "select /* pgwatch2_generated */ distinct m_name from pgwatch2.metric where m_is_active and m_is_helper" // m_name is a helper function name
		data, err := DBExecRead(configDb, CONFIGDB_IDENT, sql_helpers)
		if err != nil {
			log.Error(err)
			return err
		}
		for _, row := range data {
			metric := row["m_name"].(string)

			if strings.Contains(metric, "windows") {
				log.Infof("Skipping %s rollout. Windows helpers need to be rolled out manually", metric)
				continue
			}
			if !DoesFunctionExists(dbUnique, metric) {

				log.Debug("Trying to create metric fetching helpers for", dbUnique, metric)
				mvp, err := GetMetricVersionProperties(metric, db_pg_version, nil)
				if err != nil {
					log.Warning("Could not find query text for", dbUnique, metric)
					continue
				}
				_, err, _ = DBExecReadByDbUniqueName(dbUnique, "", 0, mvp.Sql)
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

	log.Infof("Reading preset metric config from path %s ...", path.Join(folder, PRESET_CONFIG_YAML_FILE))
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

func ParseMetricColumnAttrsFromYAML(yamlPath string) MetricColumnAttrs {
	c := MetricColumnAttrs{}

	yamlFile, err := ioutil.ReadFile(yamlPath)
	if err != nil {
		log.Errorf("Error reading file %s: %s", yamlFile, err)
		return c
	}

	err = yaml.Unmarshal(yamlFile, &c)
	if err != nil {
		log.Errorf("Unmarshaling error: %v", err)
	}
	return c
}

func ParseMetricAttrsFromYAML(yamlPath string) MetricAttrs {
	c := MetricAttrs{}

	yamlFile, err := ioutil.ReadFile(yamlPath)
	if err != nil {
		log.Errorf("Error reading file %s: %s", yamlFile, err)
		return c
	}

	err = yaml.Unmarshal(yamlFile, &c)
	if err != nil {
		log.Errorf("Unmarshaling error: %v", err)
	}
	return c
}

func ParseMetricColumnAttrsFromString(jsonAttrs string) MetricColumnAttrs {
	c := MetricColumnAttrs{}

	err := yaml.Unmarshal([]byte(jsonAttrs), &c)
	if err != nil {
		log.Errorf("Unmarshaling error: %v", err)
	}
	return c
}

func ParseMetricAttrsFromString(jsonAttrs string) MetricAttrs {
	c := MetricAttrs{}

	err := yaml.Unmarshal([]byte(jsonAttrs), &c)
	if err != nil {
		log.Errorf("Unmarshaling error: %v", err)
	}
	return c
}

// expected is following structure: metric_name/pg_ver/metric(_master|standby).sql
func ReadMetricsFromFolder(folder string, failOnError bool) (map[string]map[decimal.Decimal]MetricVersionProperties, error) {
	metrics_map := make(map[string]map[decimal.Decimal]MetricVersionProperties)
	metricNameRemapsNew := make(map[string]string)
	rIsDigitOrPunctuation := regexp.MustCompile(`^[\d\.]+$`)
	metricNamePattern := `^[a-z0-9_\.]+$`
	rMetricNameFilter := regexp.MustCompile(metricNamePattern)

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
			if !rMetricNameFilter.MatchString(f.Name()) {
				log.Warningf("Ignoring metric '%s' as name not fitting pattern: %s", f.Name(), metricNamePattern)
				continue
			}
			//log.Debugf("Processing metric: %s", f.Name())
			pgVers, err := ioutil.ReadDir(path.Join(folder, f.Name()))
			if err != nil {
				log.Error(err)
				return metrics_map, err
			}

			var metricAttrs MetricAttrs
			if _, err = os.Stat(path.Join(folder, f.Name(), "metric_attrs.yaml")); err == nil {
				metricAttrs = ParseMetricAttrsFromYAML(path.Join(folder, f.Name(), "metric_attrs.yaml"))
				//log.Debugf("Discovered following metric attributes for metric %s: %v", f.Name(), metricAttrs)
				if metricAttrs.MetricStorageName != "" {
					metricNameRemapsNew[f.Name()] = metricAttrs.MetricStorageName
				}
			}

			var metricColumnAttrs MetricColumnAttrs
			if _, err = os.Stat(path.Join(folder, f.Name(), "column_attrs.yaml")); err == nil {
				metricColumnAttrs = ParseMetricColumnAttrsFromYAML(path.Join(folder, f.Name(), "column_attrs.yaml"))
				//log.Debugf("Discovered following column attributes for metric %s: %v", f.Name(), metricColumnAttrs)
			}

			for _, pgVer := range pgVers {
				if strings.HasSuffix(pgVer.Name(), ".md") || pgVer.Name() == "column_attrs.yaml" || pgVer.Name() == "metric_attrs.yaml" {
					continue
				}
				if !rIsDigitOrPunctuation.MatchString(pgVer.Name()) {
					log.Warningf("Invalid metric structure - version folder names should consist of only numerics/dots, found: %s", pgVer.Name())
					continue
				}
				dirName, err := decimal.NewFromString(pgVer.Name())
				if err != nil {
					log.Errorf("Could not parse \"%s\" to Decimal: %s", pgVer.Name(), err)
					continue
				}
				//log.Debugf("Found %s", pgVer.Name())

				metricDefs, err := ioutil.ReadDir(path.Join(folder, f.Name(), pgVer.Name()))
				if err != nil {
					log.Error(err)
					continue
				}

				foundMetricDefFiles := make(map[string]bool) // to warn on accidental duplicates
				for _, md := range metricDefs {
					if strings.HasPrefix(md.Name(), "metric") && strings.HasSuffix(md.Name(), ".sql") {
						p := path.Join(folder, f.Name(), pgVer.Name(), md.Name())
						metric_sql, err := ioutil.ReadFile(p)
						if err != nil {
							log.Errorf("Failed to read metric definition at: %s", p)
							continue
						}
						_, exists := foundMetricDefFiles[md.Name()]
						if exists {
							log.Warningf("Multiple definitions found for metric [%s:%s], using the last one (%s)...", f.Name(), pgVer.Name(), md.Name())
						}
						foundMetricDefFiles[md.Name()] = true

						//log.Debugf("Metric definition for \"%s\" ver %s: %s", f.Name(), pgVer.Name(), metric_sql)
						mvpVer, ok := metrics_map[f.Name()]
						var mvp MetricVersionProperties
						if !ok {
							metrics_map[f.Name()] = make(map[decimal.Decimal]MetricVersionProperties)
						}
						mvp, ok = mvpVer[dirName]
						if !ok {
							mvp = MetricVersionProperties{Sql: string(metric_sql[:]), ColumnAttrs: metricColumnAttrs, MetricAttrs: metricAttrs}
						}
						mvp.CallsHelperFunctions = DoesMetricDefinitionCallHelperFunctions(mvp.Sql)
						if strings.Contains(md.Name(), "_master") {
							mvp.MasterOnly = true
						}
						if strings.Contains(md.Name(), "_standby") {
							mvp.StandbyOnly = true
						}
						if strings.Contains(md.Name(), "_su") {
							mvp.SqlSU = string(metric_sql[:])
						}
						metrics_map[f.Name()][dirName] = mvp
					}
				}
			}
		}
	}

	metricNameRemapLock.Lock()
	metricNameRemaps = metricNameRemapsNew
	metricNameRemapLock.Unlock()

	return metrics_map, nil
}

func ExpandEnvVarsForConfigEntryIfStartsWithDollar(md MonitoredDatabase) (MonitoredDatabase, int) {
	var changed int = 0

	if strings.HasPrefix(md.DBName, "$") {
		md.DBName = os.ExpandEnv(md.DBName)
		changed++
	}
	if strings.HasPrefix(md.User, "$") {
		md.User = os.ExpandEnv(md.User)
		changed++
	}
	if strings.HasPrefix(md.Password, "$") {
		md.Password = os.ExpandEnv(md.Password)
		changed++
	}
	if strings.HasPrefix(md.PasswordType, "$") {
		md.PasswordType = os.ExpandEnv(md.PasswordType)
		changed++
	}
	if strings.HasPrefix(md.DBType, "$") {
		md.DBType = os.ExpandEnv(md.DBType)
		changed++
	}
	if strings.HasPrefix(md.DBUniqueName, "$") {
		md.DBUniqueName = os.ExpandEnv(md.DBUniqueName)
		changed++
	}
	if strings.HasPrefix(md.SslMode, "$") {
		md.SslMode = os.ExpandEnv(md.SslMode)
		changed++
	}
	if strings.HasPrefix(md.DBNameIncludePattern, "$") {
		md.DBNameIncludePattern = os.ExpandEnv(md.DBNameIncludePattern)
		changed++
	}
	if strings.HasPrefix(md.DBNameExcludePattern, "$") {
		md.DBNameExcludePattern = os.ExpandEnv(md.DBNameExcludePattern)
		changed++
	}
	if strings.HasPrefix(md.PresetMetrics, "$") {
		md.PresetMetrics = os.ExpandEnv(md.PresetMetrics)
		changed++
	}
	if strings.HasPrefix(md.PresetMetricsStandby, "$") {
		md.PresetMetricsStandby = os.ExpandEnv(md.PresetMetricsStandby)
		changed++
	}

	return md, changed
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
	yamlFile = []byte(string(yamlFile))
	err = yaml.Unmarshal(yamlFile, &c)
	if err != nil {
		log.Errorf("Unmarshaling error: %v", err)
		return hostList, err
	}
	for _, v := range c {
		if v.Port == "" {
			v.Port = "5432"
		}
		if v.DBType == "" {
			v.DBType = DBTYPE_PG
		}
		if v.IsEnabled {
			log.Debugf("Found active monitoring config entry: %#v", v)
			if v.Group == "" {
				v.Group = "default"
			}
			if v.StmtTimeout == 0 {
				v.StmtTimeout = 5
			}
			vExp, changed := ExpandEnvVarsForConfigEntryIfStartsWithDollar(v)
			if changed > 0 {
				log.Debugf("[%s] %d config attributes expanded from ENV", vExp.DBUniqueName, changed)
			}
			hostList = append(hostList, vExp)
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
					hostList = append(hostList, mdbs...)
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
	var c *sqlx.DB
	var err error
	md := make([]MonitoredDatabase, 0)

	// some cloud providers limit access to template1 for some reason, so try with postgres and defaultdb (Aiven)
	templateDBsToTry := []string{"template1", "postgres", "defaultdb"}

	for _, templateDB := range templateDBsToTry {
		c, err = GetPostgresDBConnection(ce.LibPQConnStr, ce.Host, ce.Port, templateDB, ce.User, ce.Password,
			ce.SslMode, ce.SslRootCAPath, ce.SslClientCertPath, ce.SslClientKeyPath)
		if err != nil {
			return md, err
		}
		err = c.Ping()
		if err == nil {
			break
		} else {
			c.Close()
		}
	}
	if err != nil {
		return md, fmt.Errorf("Failed to connect to any of the template DBs: %v", templateDBsToTry)
	}
	defer c.Close()

	sql := `select /* pgwatch2_generated */ datname::text as datname,
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
		mainConnString := ce.LibPQConnStr
		var parsedConnString string
		if len(mainConnString) > 0 {
			if strings.Contains(mainConnString, "postgres://") || strings.Contains(mainConnString, "postgresql://") {
				parsedConnString, err = pq.ParseURL(mainConnString)
				if err != nil {
					return nil, err
				}
			} else {
				parsedConnString = mainConnString
			}
			if strings.Contains(parsedConnString, "dbname=") {
				dbRegex := regexp.MustCompile(`dbname=\'?\w+\'?`)
				parsedConnString = dbRegex.ReplaceAllString(parsedConnString, fmt.Sprintf("dbname='%s'", d["datname"].(string)))
			} else {
				parsedConnString += fmt.Sprintf(" dbname='%s'", d["datname"].(string))
			}
		}

		md = append(md, MonitoredDatabase{
			LibPQConnStr:         parsedConnString,
			DBUniqueName:         ce.DBUniqueName + "_" + d["datname_escaped"].(string),
			DBUniqueNameOrig:     ce.DBUniqueName,
			DBName:               d["datname"].(string),
			Host:                 ce.Host,
			Port:                 ce.Port,
			User:                 ce.User,
			Password:             ce.Password,
			PasswordType:         ce.PasswordType,
			SslMode:              ce.SslMode,
			SslRootCAPath:        ce.SslRootCAPath,
			SslClientCertPath:    ce.SslClientCertPath,
			SslClientKeyPath:     ce.SslClientKeyPath,
			StmtTimeout:          ce.StmtTimeout,
			Metrics:              ce.Metrics,
			MetricsStandby:       ce.MetricsStandby,
			PresetMetrics:        ce.PresetMetrics,
			PresetMetricsStandby: ce.PresetMetricsStandby,
			IsSuperuser:          ce.IsSuperuser,
			CustomTags:           ce.CustomTags,
			HostConfig:           ce.HostConfig,
			OnlyIfMaster:         ce.OnlyIfMaster,
			DBType:               ce.DBType})
	}

	return md, err
}

// Resolves regexes if exact DBs were not specified exact
func GetMonitoredDatabasesFromMonitoringConfig(mc []MonitoredDatabase) []MonitoredDatabase {
	md := make([]MonitoredDatabase, 0)
	if len(mc) == 0 {
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
		if _, ok := dbTypeMap[e.DBType]; !ok {
			log.Warningf("Ignoring host \"%s\" - unknown dbtype: %s. Expected one of: %+v", e.DBUniqueName, e.DBType, dbTypes)
			continue
		}
		if e.IsEnabled && e.PasswordType == "aes-gcm-256" && opts.AesGcmKeyphrase != "" {
			e.Password = decrypt(e.DBUniqueName, opts.AesGcmKeyphrase, e.Password)
		}
		if e.DBType == DBTYPE_PATRONI && e.DBName == "" {
			log.Warningf("Ignoring host \"%s\" as \"dbname\" attribute not specified but required by dbtype=patroni", e.DBUniqueName)
			continue
		}
		if e.DBType == DBTYPE_PG && e.DBName == "" {
			log.Warningf("Ignoring host \"%s\" as \"dbname\" attribute not specified but required by dbtype=postgres", e.DBUniqueName)
			continue
		}
		if len(e.DBName) == 0 || e.DBType == DBTYPE_PG_CONT || e.DBType == DBTYPE_PATRONI || e.DBType == DBTYPE_PATRONI_CONT || e.DBType == DBTYPE_PATRONI_NAMESPACE_DISCOVERY {
			if e.DBType == DBTYPE_PG_CONT {
				log.Debugf("Adding \"%s\" (host=%s, port=%s) to continuous monitoring ...", e.DBUniqueName, e.Host, e.Port)
			}
			var found_dbs []MonitoredDatabase
			var err error

			if e.DBType == DBTYPE_PATRONI || e.DBType == DBTYPE_PATRONI_CONT || e.DBType == DBTYPE_PATRONI_NAMESPACE_DISCOVERY {
				found_dbs, err = ResolveDatabasesFromPatroni(e)
			} else {
				found_dbs, err = ResolveDatabasesFromConfigEntry(e)
			}
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
	"totalMetricsReusedFromCacheCounter": %d,
	"totalDatasetsFetchedCounter": %d,
	"metricPointsPerMinuteLast5MinAvg": %v,
	"metricsDropped": %d,
	"totalMetricFetchFailuresCounter": %d,
	"datastoreWriteFailuresCounter": %d,
	"datastoreSuccessfulWritesCounter": %d,
	"datastoreAvgSuccessfulWriteTimeMillis": %.1f,
	"databasesMonitored": %d,
	"databasesConfigured": %d,
	"unreachableDBs": %d,
	"gathererUptimeSeconds": %d
}
`
	now := time.Now()
	secondsFromLastSuccessfulDatastoreWrite := atomic.LoadInt64(&lastSuccessfulDatastoreWriteTimeEpoch)
	totalMetrics := atomic.LoadUint64(&totalMetricsFetchedCounter)
	cacheMetrics := atomic.LoadUint64(&totalMetricsReusedFromCacheCounter)
	totalDatasets := atomic.LoadUint64(&totalDatasetsFetchedCounter)
	metricsDropped := atomic.LoadUint64(&totalMetricsDroppedCounter)
	metricFetchFailuresCounter := atomic.LoadUint64(&totalMetricFetchFailuresCounter)
	datastoreFailures := atomic.LoadUint64(&datastoreWriteFailuresCounter)
	datastoreSuccess := atomic.LoadUint64(&datastoreWriteSuccessCounter)
	datastoreTotalTimeMicros := atomic.LoadUint64(&datastoreTotalWriteTimeMicroseconds) // successful writes only
	datastoreAvgSuccessfulWriteTimeMillis := float64(datastoreTotalTimeMicros) / float64(datastoreSuccess) / 1000.0
	gathererUptimeSeconds := uint64(now.Sub(gathererStartTime).Seconds())
	var metricPointsPerMinute int64
	metricPointsPerMinute = atomic.LoadInt64(&metricPointsPerMinuteLast5MinAvg)
	if metricPointsPerMinute == -1 { // calculate avg. on the fly if 1st summarization hasn't happened yet
		metricPointsPerMinute = int64((totalMetrics * 60) / gathererUptimeSeconds)
	}
	monitoredDbs := getMonitoredDatabasesSnapshot()
	databasesConfigured := len(monitoredDbs) // including replicas
	databasesMonitored := 0
	for _, md := range monitoredDbs {
		if shouldDbBeMonitoredBasedOnCurrentState(md) {
			databasesMonitored++
		}
	}
	unreachableDBsLock.RLock()
	unreachableDBs := len(unreachableDB)
	unreachableDBsLock.RUnlock()
	_, _ = io.WriteString(w, fmt.Sprintf(jsonResponseTemplate, time.Now().Unix()-secondsFromLastSuccessfulDatastoreWrite, totalMetrics, cacheMetrics, totalDatasets, metricPointsPerMinute, metricsDropped, metricFetchFailuresCounter, datastoreFailures, datastoreSuccess, datastoreAvgSuccessfulWriteTimeMillis, databasesMonitored, databasesConfigured, unreachableDBs, gathererUptimeSeconds))
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
	for now := range ticker.C {
		currentMetricsCounterValue = atomic.LoadUint64(&totalMetricsFetchedCounter)
		atomic.StoreInt64(&metricPointsPerMinuteLast5MinAvg, int64(math.Round(float64(currentMetricsCounterValue-prevMetricsCounterValue)*60/now.Sub(lastSummarization).Seconds())))
		prevMetricsCounterValue = currentMetricsCounterValue
		lastSummarization = now
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

func encrypt(passphrase, plaintext string) string { // called when --password-to-encrypt set
	key, salt := deriveKey(passphrase, nil)
	iv := make([]byte, 12)
	_, _ = rand.Read(iv)
	b, _ := aes.NewCipher(key)
	aesgcm, _ := cipher.NewGCM(b)
	data := aesgcm.Seal(nil, iv, []byte(plaintext), nil)
	return hex.EncodeToString(salt) + "-" + hex.EncodeToString(iv) + "-" + hex.EncodeToString(data)
}

func deriveKey(passphrase string, salt []byte) ([]byte, []byte) {
	if salt == nil {
		salt = make([]byte, 8)
		_, _ = rand.Read(salt)
	}
	return pbkdf2.Key([]byte(passphrase), salt, 1000, 32, sha256.New), salt
}

func decrypt(dbUnique, passphrase, ciphertext string) string {
	arr := strings.Split(ciphertext, "-")
	if len(arr) != 3 {
		log.Warningf("Aes-gcm-256 encrypted password for \"%s\" should consist of 3 parts - using 'as is'", dbUnique)
		return ciphertext
	}
	salt, _ := hex.DecodeString(arr[0])
	iv, _ := hex.DecodeString(arr[1])
	data, _ := hex.DecodeString(arr[2])
	key, _ := deriveKey(passphrase, salt)
	b, _ := aes.NewCipher(key)
	aesgcm, _ := cipher.NewGCM(b)
	data, _ = aesgcm.Open(nil, iv, data, nil)
	//log.Debug("decoded", string(data))
	return string(data)
}

func SyncMonitoredDBsToDatastore(monitored_dbs []MonitoredDatabase, persistence_channel chan []MetricStoreMessage) {
	if len(monitored_dbs) > 0 {
		msms := make([]MetricStoreMessage, len(monitored_dbs))
		now := time.Now()

		for _, mdb := range monitored_dbs {
			var db = make(map[string]interface{})
			db["tag_group"] = mdb.Group
			db["master_only"] = mdb.OnlyIfMaster
			db["epoch_ns"] = now.UnixNano()
			db["continuous_discovery_prefix"] = mdb.DBUniqueNameOrig
			for k, v := range mdb.CustomTags {
				db["tag_"+k] = v
			}
			var data = [](map[string]interface{}){db}
			msms = append(msms, MetricStoreMessage{DBUniqueName: mdb.DBUniqueName, MetricName: MONITORED_DBS_DATASTORE_SYNC_METRIC_NAME,
				Data: data})
		}
		persistence_channel <- msms
	}
}

func CheckFolderExistsAndReadable(path string) bool {
	if _, err := ioutil.ReadDir(path); err != nil {
		return false
	}
	return true
}

func goPsutilCalcCPUUtilization(probe0, probe1 cpu.TimesStat) float64 {
	return 100 - (100.0 * (probe1.Idle - probe0.Idle + probe1.Iowait - probe0.Iowait + probe1.Steal - probe0.Steal) / (probe1.Total() - probe0.Total()))
}

// Simulates "psutil" metric output. Assumes the result from last call as input, otherwise uses a 1s measurement
// https://github.com/cybertec-postgresql/pgwatch2/blob/master/pgwatch2/metrics/psutil_cpu/9.0/metric.sql
func GetGoPsutilCPU(interval time.Duration) ([]map[string]interface{}, error) {
	prevCPULoadTimeStatsLock.RLock()
	prevTime := prevCPULoadTimestamp
	prevTimeStat := prevCPULoadTimeStats
	prevCPULoadTimeStatsLock.RUnlock()

	if prevTime.IsZero() || (time.Now().UnixNano()-prevTime.UnixNano()) < 1e9 { // give "short" stats on first run, based on a 1s probe
		probe0, err := cpu.Times(false)
		if err != nil {
			return nil, err
		}
		prevTimeStat = probe0[0]
		time.Sleep(1e9)
	}

	curCallStats, err := cpu.Times(false)
	if err != nil {
		return nil, err
	}
	if prevTime.IsZero() || time.Now().UnixNano()-prevTime.UnixNano() < 1e9 || time.Now().Unix()-prevTime.Unix() >= int64(interval.Seconds()) {
		prevCPULoadTimeStatsLock.Lock() // update the cache
		prevCPULoadTimeStats = curCallStats[0]
		prevCPULoadTimestamp = time.Now()
		prevCPULoadTimeStatsLock.Unlock()
	}

	la, err := load.Avg()
	if err != nil {
		return nil, err
	}

	cpus, err := cpu.Counts(true)
	if err != nil {
		return nil, err
	}

	retMap := make(map[string]interface{})
	retMap["epoch_ns"] = time.Now().UnixNano()
	retMap["cpu_utilization"] = math.Round(100*goPsutilCalcCPUUtilization(prevTimeStat, curCallStats[0])) / 100
	retMap["load_1m_norm"] = math.Round(100*la.Load1/float64(cpus)) / 100
	retMap["load_1m"] = math.Round(100*la.Load1) / 100
	retMap["load_5m_norm"] = math.Round(100*la.Load5/float64(cpus)) / 100
	retMap["load_5m"] = math.Round(100*la.Load5) / 100
	retMap["user"] = math.Round(10000.0*(curCallStats[0].User-prevTimeStat.User)/(curCallStats[0].Total()-prevTimeStat.Total())) / 100
	retMap["system"] = math.Round(10000.0*(curCallStats[0].System-prevTimeStat.System)/(curCallStats[0].Total()-prevTimeStat.Total())) / 100
	retMap["idle"] = math.Round(10000.0*(curCallStats[0].Idle-prevTimeStat.Idle)/(curCallStats[0].Total()-prevTimeStat.Total())) / 100
	retMap["iowait"] = math.Round(10000.0*(curCallStats[0].Iowait-prevTimeStat.Iowait)/(curCallStats[0].Total()-prevTimeStat.Total())) / 100
	retMap["irqs"] = math.Round(10000.0*(curCallStats[0].Irq-prevTimeStat.Irq+curCallStats[0].Softirq-prevTimeStat.Softirq)/(curCallStats[0].Total()-prevTimeStat.Total())) / 100
	retMap["other"] = math.Round(10000.0*(curCallStats[0].Steal-prevTimeStat.Steal+curCallStats[0].Guest-prevTimeStat.Guest+curCallStats[0].GuestNice-prevTimeStat.GuestNice)/(curCallStats[0].Total()-prevTimeStat.Total())) / 100

	return []map[string]interface{}{retMap}, nil
}

func GetGoPsutilMem() ([]map[string]interface{}, error) {
	vm, err := mem.VirtualMemory()
	if err != nil {
		return nil, err
	}

	retMap := make(map[string]interface{})
	retMap["epoch_ns"] = time.Now().UnixNano()
	retMap["total"] = int64(vm.Total)
	retMap["used"] = int64(vm.Used)
	retMap["free"] = int64(vm.Free)
	retMap["buff_cache"] = int64(vm.Buffers)
	retMap["available"] = int64(vm.Available)
	retMap["percent"] = math.Round(100*vm.UsedPercent) / 100
	retMap["swap_total"] = int64(vm.SwapTotal)
	retMap["swap_used"] = int64(vm.SwapCached)
	retMap["swap_free"] = int64(vm.SwapFree)
	retMap["swap_percent"] = math.Round(100*float64(vm.SwapCached)/float64(vm.SwapTotal)) / 100

	return []map[string]interface{}{retMap}, nil
}

func GetGoPsutilDiskTotals() ([]map[string]interface{}, error) {
	d, err := disk.IOCounters()
	if err != nil {
		return nil, err
	}

	retMap := make(map[string]interface{})
	var readBytes, writeBytes, reads, writes float64

	retMap["epoch_ns"] = time.Now().UnixNano()
	for _, v := range d { // summarize all disk devices
		readBytes += float64(v.ReadBytes) // datatype float is just an oversight in the original psutil helper
		// but can't change it without causing problems on storage level (InfluxDB)
		writeBytes += float64(v.WriteBytes)
		reads += float64(v.ReadCount)
		writes += float64(v.WriteCount)
	}
	retMap["read_bytes"] = readBytes
	retMap["write_bytes"] = writeBytes
	retMap["read_count"] = reads
	retMap["write_count"] = writes

	return []map[string]interface{}{retMap}, nil
}

func getPathUnderlyingDeviceId(path string) (uint64, error) {
	fp, err := os.Open(path)
	if err != nil {
		return 0, err
	}
	fi, err := fp.Stat()
	if err != nil {
		return 0, err
	}
	stat := fi.Sys().(*syscall.Stat_t)
	return stat.Dev, nil
}

// connects actually to the instance to determine PG relevant disk paths / mounts
func GetGoPsutilDiskPG(dbUnique string) ([]map[string]interface{}, error) {
	sql := `select current_setting('data_directory') as dd, current_setting('log_directory') as ld, current_setting('server_version_num')::int as pgver`
	sqlTS := `select spcname::text as name, pg_catalog.pg_tablespace_location(oid) as location from pg_catalog.pg_tablespace where not spcname like any(array[E'pg\\_%'])`
	var ddDevice, ldDevice, walDevice uint64

	data, err, _ := DBExecReadByDbUniqueName(dbUnique, "", 0, sql)
	if err != nil || len(data) == 0 {
		log.Errorf("Failed to determine relevant PG disk paths via SQL: %v", err)
		return nil, err
	}

	dataDirPath := data[0]["dd"].(string)
	ddUsage, err := disk.Usage(dataDirPath)
	if err != nil {
		log.Errorf("Could not determine disk usage for path %v: %v", dataDirPath, err)
		return nil, err
	}

	retRows := make([]map[string]interface{}, 0)
	epoch_ns := time.Now().UnixNano()
	dd := make(map[string]interface{})
	dd["epoch_ns"] = epoch_ns
	dd["tag_dir_or_tablespace"] = "data_directory"
	dd["tag_path"] = dataDirPath
	dd["total"] = float64(ddUsage.Total)
	dd["used"] = float64(ddUsage.Used)
	dd["free"] = float64(ddUsage.Free)
	dd["percent"] = math.Round(100*ddUsage.UsedPercent) / 100
	retRows = append(retRows, dd)

	ddDevice, err = getPathUnderlyingDeviceId(dataDirPath)
	if err != nil {
		log.Errorf("Could not determine disk device ID of data_directory %v: %v", dataDirPath, err)
	}

	logDirPath := data[0]["ld"].(string)
	if !strings.HasPrefix(logDirPath, "/") {
		logDirPath = path.Join(dataDirPath, logDirPath)
	}
	if len(logDirPath) > 0 && CheckFolderExistsAndReadable(logDirPath) { // syslog etc considered out of scope
		ldDevice, err = getPathUnderlyingDeviceId(logDirPath)
		if err != nil {
			log.Infof("Could not determine disk device ID of log_directory %v: %v", logDirPath, err)
		}
		if err != nil || ldDevice != ddDevice { // no point to report same data in case of single folder configuration
			ld := make(map[string]interface{})
			ldUsage, err := disk.Usage(logDirPath)
			if err != nil {
				log.Infof("Could not determine disk usage for path %v: %v", logDirPath, err)
			} else {
				ld["epoch_ns"] = epoch_ns
				ld["tag_dir_or_tablespace"] = "log_directory"
				ld["tag_path"] = logDirPath
				ld["total"] = float64(ldUsage.Total)
				ld["used"] = float64(ldUsage.Used)
				ld["free"] = float64(ldUsage.Free)
				ld["percent"] = math.Round(100*ldUsage.UsedPercent) / 100
				retRows = append(retRows, ld)
			}
		}
	}

	var walDirPath string
	if CheckFolderExistsAndReadable(path.Join(dataDirPath, "pg_wal")) {
		walDirPath = path.Join(dataDirPath, "pg_wal")
	} else if CheckFolderExistsAndReadable(path.Join(dataDirPath, "pg_xlog")) {
		walDirPath = path.Join(dataDirPath, "pg_xlog") // < v10
	}

	if len(walDirPath) > 0 {
		walDevice, err = getPathUnderlyingDeviceId(walDirPath)
		if err != nil {
			log.Infof("Could not determine disk device ID of WAL directory %v: %v", walDirPath, err) // storing anyways
		}

		if err != nil || walDevice != ddDevice || walDevice != ldDevice { // no point to report same data in case of single folder configuration
			walUsage, err := disk.Usage(walDirPath)
			if err != nil {
				log.Errorf("Could not determine disk usage for WAL directory %v: %v", walDirPath, err)
			} else {
				wd := make(map[string]interface{})
				wd["epoch_ns"] = epoch_ns
				wd["tag_dir_or_tablespace"] = "pg_wal"
				wd["tag_path"] = walDirPath
				wd["total"] = float64(walUsage.Total)
				wd["used"] = float64(walUsage.Used)
				wd["free"] = float64(walUsage.Free)
				wd["percent"] = math.Round(100*walUsage.UsedPercent) / 100
				retRows = append(retRows, wd)
			}
		}
	}

	data, err, _ = DBExecReadByDbUniqueName(dbUnique, "", 0, sqlTS)
	if err != nil {
		log.Infof("Failed to determine relevant PG tablespace paths via SQL: %v", err)
	} else if len(data) > 0 {
		for _, row := range data {
			tsPath := row["location"].(string)
			tsName := row["name"].(string)

			tsDevice, err := getPathUnderlyingDeviceId(tsPath)
			if err != nil {
				log.Errorf("Could not determine disk device ID of tablespace %s (%s): %v", tsName, tsPath, err)
				continue
			}

			if tsDevice == ddDevice || tsDevice == ldDevice || tsDevice == walDevice {
				continue
			}
			tsUsage, err := disk.Usage(tsPath)
			if err != nil {
				log.Errorf("Could not determine disk usage for tablespace %s, directory %s: %v", row["name"].(string), row["location"].(string), err)
			}
			ts := make(map[string]interface{})
			ts["epoch_ns"] = epoch_ns
			ts["tag_dir_or_tablespace"] = tsName
			ts["tag_path"] = tsPath
			ts["total"] = float64(tsUsage.Total)
			ts["used"] = float64(tsUsage.Used)
			ts["free"] = float64(tsUsage.Free)
			ts["percent"] = math.Round(100*tsUsage.UsedPercent) / 100
			retRows = append(retRows, ts)
		}
	}

	return retRows, nil
}

func GetLoadAvgLocal() ([]map[string]interface{}, error) {
	la, err := load.Avg()
	if err != nil {
		log.Errorf("Could not inquiry local system load average: %v", err)
		return nil, err
	}

	row := make(map[string]interface{})
	row["epoch_ns"] = time.Now().UnixNano()
	row["load_1min"] = la.Load1
	row["load_5min"] = la.Load5
	row["load_15min"] = la.Load15

	return []map[string]interface{}{row}, nil
}

func shouldDbBeMonitoredBasedOnCurrentState(md MonitoredDatabase) bool {
	return !IsDBDormant(md.DBUniqueName)
}

func ControlChannelsMapToList(control_channels map[string]chan ControlMessage) []string {
	control_channel_list := make([]string, len(control_channels))
	i := 0
	for key := range control_channels {
		control_channel_list[i] = key
		i++
	}
	return control_channel_list
}

func DoCloseResourcesForRemovedMonitoredDBIfAny(dbUnique string) {

	CloseOrLimitSqlConnPoolForMonitoredDBIfAny(dbUnique)

	PurgeMetricsFromPromAsyncCacheIfAny(dbUnique, "")
}

func CloseResourcesForRemovedMonitoredDBs(currentDBs, prevLoopDBs []MonitoredDatabase, shutDownDueToRoleChange map[string]bool) {
	var curDBsMap = make(map[string]bool)

	for _, curDB := range currentDBs {
		curDBsMap[curDB.DBUniqueName] = true
	}

	for _, prevDB := range prevLoopDBs {
		if _, ok := curDBsMap[prevDB.DBUniqueName]; !ok { // removed from config
			DoCloseResourcesForRemovedMonitoredDBIfAny(prevDB.DBUniqueName)
		}
	}

	// or to be ignored due to current instance state
	for roleChangedDB := range shutDownDueToRoleChange {
		DoCloseResourcesForRemovedMonitoredDBIfAny(roleChangedDB)
	}
}

func PromAsyncCacheInitIfRequired(dbUnique, metric string) { // cache structure: [dbUnique][metric]lastly_fetched_data
	if opts.Datastore == DATASTORE_PROMETHEUS && promAsyncMode {
		promAsyncMetricCacheLock.Lock()
		defer promAsyncMetricCacheLock.Unlock()
		if _, ok := promAsyncMetricCache[dbUnique]; !ok {
			metricMap := make(map[string][]MetricStoreMessage)
			promAsyncMetricCache[dbUnique] = metricMap
		}
	}
}

func PromAsyncCacheAddMetricData(dbUnique, metric string, msgArr []MetricStoreMessage) { // cache structure: [dbUnique][metric]lastly_fetched_data
	promAsyncMetricCacheLock.Lock()
	defer promAsyncMetricCacheLock.Unlock()
	if _, ok := promAsyncMetricCache[dbUnique]; ok {
		promAsyncMetricCache[dbUnique][metric] = msgArr
	}
}

func SetUndersizedDBState(dbUnique string, state bool) {
	undersizedDBsLock.Lock()
	undersizedDBs[dbUnique] = state
	undersizedDBsLock.Unlock()
}

func IsDBUndersized(dbUnique string) bool {
	undersizedDBsLock.RLock()
	defer undersizedDBsLock.RUnlock()
	undersized, ok := undersizedDBs[dbUnique]
	if ok {
		return undersized
	}
	return false
}

func SetRecoveryIgnoredDBState(dbUnique string, state bool) {
	recoveryIgnoredDBsLock.Lock()
	recoveryIgnoredDBs[dbUnique] = state
	recoveryIgnoredDBsLock.Unlock()
}

func IsDBIgnoredBasedOnRecoveryState(dbUnique string) bool {
	recoveryIgnoredDBsLock.RLock()
	defer recoveryIgnoredDBsLock.RUnlock()
	recoveryIgnored, ok := undersizedDBs[dbUnique]
	if ok {
		return recoveryIgnored
	}
	return false
}

func IsDBDormant(dbUnique string) bool {
	return IsDBUndersized(dbUnique) || IsDBIgnoredBasedOnRecoveryState(dbUnique)
}

func DoesEmergencyTriggerfileExist() bool {
	// Main idea of the feature is to be able to quickly free monitored DBs / network of any extra "monitoring effect" load.
	// In highly automated K8s / IaC environments such a temporary change might involve pull requests, peer reviews, CI/CD etc
	// which can all take too long vs "exec -it pgwatch2-pod -- touch /tmp/pgwatch2-emergency-pause".
	// NB! After creating the file it can still take up to --servers-refresh-loop-seconds (2min def.) for change to take effect!
	if opts.EmergencyPauseTriggerfile == "" {
		return false
	}
	_, err := os.Stat(opts.EmergencyPauseTriggerfile)
	return err == nil
}

func DoesMetricDefinitionCallHelperFunctions(sqlDefinition string) bool {
	if !noHelperFunctions { // save on regex matching --no-helper-functions param not set, information will not be used then anyways
		return false
	}
	return regexSQLHelperFunctionCalled.MatchString(sqlDefinition)
}

type Options struct {
	// Slice of bool will append 'true' each time the option
	// is encountered (can be set multiple times, like -vvv)
	Verbose              string `short:"v" long:"verbose" description:"Chat level [DEBUG|INFO|WARN]. Default: WARN" env:"PW2_VERBOSE"`
	Host                 string `long:"host" description:"PG config DB host" default:"localhost" env:"PW2_PGHOST"`
	Port                 string `short:"p" long:"port" description:"PG config DB port" default:"5432" env:"PW2_PGPORT"`
	Dbname               string `short:"d" long:"dbname" description:"PG config DB dbname" default:"pgwatch2" env:"PW2_PGDATABASE"`
	User                 string `short:"u" long:"user" description:"PG config DB user" default:"pgwatch2" env:"PW2_PGUSER"`
	Password             string `long:"password" description:"PG config DB password" env:"PW2_PGPASSWORD"`
	PgRequireSSL         string `long:"pg-require-ssl" description:"PG config DB SSL connection only" default:"false" env:"PW2_PGSSL"`
	Group                string `short:"g" long:"group" description:"Group (or groups, comma separated) for filtering which DBs to monitor. By default all are monitored" env:"PW2_GROUP"`
	Datastore            string `long:"datastore" description:"[influx|postgres|prometheus|graphite|json]" default:"influx" env:"PW2_DATASTORE"`
	PGMetricStoreConnStr string `long:"pg-metric-store-conn-str" description:"PG Metric Store" env:"PW2_PG_METRIC_STORE_CONN_STR"`
	PGRetentionDays      int64  `long:"pg-retention-days" description:"If set, metrics older than that will be deleted" default:"14" env:"PW2_PG_RETENTION_DAYS"`
	PrometheusPort       int64  `long:"prometheus-port" description:"Prometheus port. Effective with --datastore=prometheus" default:"9187" env:"PW2_PROMETHEUS_PORT"`
	PrometheusListenAddr string `long:"prometheus-listen-addr" description:"Network interface to listen on" default:"0.0.0.0" env:"PW2_PROMETHEUS_LISTEN_ADDR"`
	PrometheusNamespace  string `long:"prometheus-namespace" description:"Prefix for all non-process (thus Postgres) metrics" default:"pgwatch2" env:"PW2_PROMETHEUS_NAMESPACE"`
	PrometheusAsyncMode  string `long:"prometheus-async-mode" description:"Gather in background as with other storage and cache last fetch results in memory" default:"false" env:"PW2_PROMETHEUS_ASYNC_MODE"`
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
	InfluxRetentionDays  int64  `long:"iretentiondays" description:"Retention period in days. Set to 0 to use database defaults for an existing DB [default: 30]" default:"30" env:"PW2_IRETENTIONDAYS"`
	InfluxRetentionName  string `long:"iretentionname" description:"Retention policy name. [Default: pgwatch_def_ret]" default:"pgwatch_def_ret" env:"PW2_IRETENTIONNAME"`
	GraphiteHost         string `long:"graphite-host" description:"Graphite host" env:"PW2_GRAPHITEHOST"`
	GraphitePort         string `long:"graphite-port" description:"Graphite port" env:"PW2_GRAPHITEPORT"`
	JsonStorageFile      string `long:"json-storage-file" description:"Path to file where metrics will be stored when --datastore=json, one metric set per line" env:"PW2_JSON_STORAGE_FILE"`
	// Params for running based on local config files, enabled distributed "push model" based metrics gathering. Metrics are sent directly to Influx/Graphite.
	Config                  string `short:"c" long:"config" description:"File or folder of YAML files containing info on which DBs to monitor and where to store metrics" env:"PW2_CONFIG"`
	MetricsFolder           string `short:"m" long:"metrics-folder" description:"Folder of metrics definitions" env:"PW2_METRICS_FOLDER"`
	BatchingDelayMs         int64  `long:"batching-delay-ms" description:"Max milliseconds to wait for a batched metrics flush. [Default: 250]" default:"250" env:"PW2_BATCHING_MAX_DELAY_MS"`
	AdHocConnString         string `long:"adhoc-conn-str" description:"Ad-hoc mode: monitor a single Postgres DB specified by a standard Libpq connection string" env:"PW2_ADHOC_CONN_STR"`
	AdHocDBType             string `long:"adhoc-dbtype" description:"Ad-hoc mode: postgres|postgres-continuous-discovery" default:"postgres" env:"PW2_ADHOC_DBTYPE"`
	AdHocConfig             string `long:"adhoc-config" description:"Ad-hoc mode: a preset config name or a custom JSON config" env:"PW2_ADHOC_CONFIG"`
	AdHocCreateHelpers      string `long:"adhoc-create-helpers" description:"Ad-hoc mode: try to auto-create helpers. Needs superuser to succeed [Default: false]" default:"false" env:"PW2_ADHOC_CREATE_HELPERS"`
	AdHocUniqueName         string `long:"adhoc-name" description:"Ad-hoc mode: Unique 'dbname' for Influx. [Default: adhoc]" default:"adhoc" env:"PW2_ADHOC_NAME"`
	InternalStatsPort       int64  `long:"internal-stats-port" description:"Port for inquiring monitoring status in JSON format. [Default: 8081]" default:"8081" env:"PW2_INTERNAL_STATS_PORT"`
	DirectOSStats           string `long:"direct-os-stats" description:"Extract OS related psutil statistics not via PL/Python wrappers but directly on host [Default: off]" default:"off" env:"PW2_DIRECT_OS_STATS"`
	ConnPooling             string `long:"conn-pooling" description:"Enable re-use of metrics fetching connections [Default: off]" default:"off" env:"PW2_CONN_POOLING"`
	AesGcmKeyphrase         string `long:"aes-gcm-keyphrase" description:"Decryption key for AES-GCM-256 passwords" env:"PW2_AES_GCM_KEYPHRASE"`
	AesGcmKeyphraseFile     string `long:"aes-gcm-keyphrase-file" description:"File with decryption key for AES-GCM-256 passwords" env:"PW2_AES_GCM_KEYPHRASE_FILE"`
	AesGcmPasswordToEncrypt string `long:"aes-gcm-password-to-encrypt" description:"A special mode, returns the encrypted plain-text string and quits. Keyphrase(file) must be set. Useful for YAML mode" env:"PW2_AES_GCM_PASSWORD_TO_ENCRYPT"`
	// NB! "Test data" mode needs to be combined with "ad-hoc" mode to get an initial set of metrics from a real source
	TestdataMultiplier           int    `long:"testdata-multiplier" description:"For how many hosts to generate data" env:"PW2_TESTDATA_MULTIPLIER"`
	TestdataDays                 int    `long:"testdata-days" description:"For how many days to generate data" env:"PW2_TESTDATA_DAYS"`
	AddRealDbname                string `long:"add-real-dbname" description:"Add real DB name to each captured metric" env:"PW2_ADD_REAL_DBNAME" default:"false"`
	RealDbnameField              string `long:"real-dbname-field" description:"Tag key for real DB name if --add-real-dbname enabled" env:"PW2_REAL_DBNAME_FIELD" default:"real_dbname"`
	AddSystemIdentifier          string `long:"add-system-identifier" description:"Add system identifier to each captured metric" env:"PW2_ADD_SYSTEM_IDENTIFIER" default:"false"`
	SystemIdentifierField        string `long:"system-identifier-field" description:"Tag key for system identifier value if --add-system-identifier" env:"PW2_SYSTEM_IDENTIFIER_FIELD" default:"sys_id"`
	ServersRefreshLoopSeconds    int    `long:"servers-refresh-loop-seconds" description:"Sleep time for the main loop" env:"PW2_SERVERS_REFRESH_LOOP_SECONDS" default:"120"`
	InstanceLevelCacheMaxSeconds int64  `long:"instance-level-cache-max-seconds" description:"Max allowed staleness for instance level metric data shared between DBs of an instance. Affects 'continuous' host types only. Set to 0 to disable" env:"PW2_INSTANCE_LEVEL_CACHE_MAX_SECONDS" default:"30"`
	MinDbSizeMB                  int64  `long:"min-db-size-mb" description:"Smaller size DBs will be ignored and not monitored until they reach the threshold." env:"PW2_MIN_DB_SIZE_MB" default:"0"`
	MaxParallelConnectionsPerDb  int    `long:"max-parallel-connections-per-db" description:"Max parallel metric fetches per DB. Note the multiplication effect on multi-DB instances" env:"PW2_MAX_PARALLEL_CONNECTIONS_PER_DB" default:"2"`
	Version                      bool   `long:"version" description:"Show Git build version and exit" env:"PW2_VERSION"`
	Ping                         bool   `long:"ping" description:"Try to connect to all configured DB-s, report errors and then exit" env:"PW2_PING"`
	EmergencyPauseTriggerfile    string `long:"emergency-pause-triggerfile" description:"When the file exists no metrics will be temporarily fetched / scraped" env:"PW2_EMERGENCY_PAUSE_TRIGGERFILE" default:"/tmp/pgwatch2-emergency-pause"`
	NoHelperFunctions            string `long:"no-helper-functions" description:"Ignore metric definitions using helper functions (in form get_smth()) and don't also roll out any helpers automatically" env:"PW2_NO_HELPER_FUNCTIONS" default:"false"`
	TryCreateListedExtsIfMissing string `long:"try-create-listed-exts-if-missing" description:"Try creating the listed extensions (comma sep.) on first connect for all monitored DBs when missing. Main usage - pg_stat_statements" env:"PW2_TRY_CREATE_LISTED_EXTS_IF_MISSING" default:""`
}

var opts Options

func main() {
	var err error
	parser := flags.NewParser(&opts, flags.Default)

	if _, err = parser.Parse(); err != nil {
		return
	}

	if opts.Version {
		if commit == "" {
			fmt.Println("Git version not set! Use the 'build_gatherer.sh' script to build the binary or specify 'commit' and 'date' via -ldflags...")
			os.Exit(1)
		}
		fmt.Printf("%s (%s)\n", commit, date)
		os.Exit(0)
	}

	if strings.ToUpper(opts.Verbose) == "DEBUG" {
		logging.SetLevel(logging.DEBUG, "main")
	} else if strings.ToUpper(opts.Verbose) == "INFO" {
		logging.SetLevel(logging.INFO, "main")
	} else if strings.HasPrefix(strings.ToUpper(opts.Verbose), "WARN") {
		logging.SetLevel(logging.WARNING, "main")
	} else {
		if len(opts.Verbose) >= 2 {
			logging.SetLevel(logging.DEBUG, "main")
		} else if len(opts.Verbose) == 1 {
			logging.SetLevel(logging.INFO, "main")
		} else {
			logging.SetLevel(logging.WARNING, "main")
		}
	}
	logging.SetFormatter(logging.MustStringFormatter(`%{level:.4s} %{shortfunc}: %{message}`))

	log.Debugf("opts: %+v", opts)

	tryDirectOSStats = StringToBoolOrFail(opts.DirectOSStats, "--direct-os-stats")

	if opts.ServersRefreshLoopSeconds <= 1 {
		log.Fatal("--servers-refresh-loop-seconds must be greater than 1")
	}

	if opts.MaxParallelConnectionsPerDb < 1 {
		log.Fatal("--max-parallel-connections-per-db must be >= 1")
	}

	if len(opts.InfluxSSLSkipVerify) > 0 {
		var err error
		InfluxSkipSSLCertVerify, err = strconv.ParseBool(opts.InfluxSSLSkipVerify)
		if err != nil {
			log.Fatal("Invalid --issl-skip-verify input: strconv.ParseBool compatible expected")
		}
	}

	if len(opts.InfluxSSLSkipVerify2) > 0 {
		var err error
		InfluxSkipSSLCertVerify2, err = strconv.ParseBool(opts.InfluxSSLSkipVerify2)
		if err != nil {
			log.Fatal("Invalid --issl-skip-verify2 input: strconv.ParseBool compatible expected")
		}
	}

	if len(opts.AesGcmKeyphraseFile) > 0 {
		_, err := os.Stat(opts.AesGcmKeyphraseFile)
		if os.IsNotExist(err) {
			log.Warningf("Failed to read aes_gcm_keyphrase_file at %s, thus cannot monitor hosts with encrypted passwords", opts.AesGcmKeyphraseFile)
		} else {
			keyBytes, err := ioutil.ReadFile(opts.AesGcmKeyphraseFile)
			if err != nil {
				log.Fatalf("Failed to read aes_gcm_keyphrase_file at %s: %v", opts.AesGcmKeyphraseFile, err)
			}
			if keyBytes[len(keyBytes)-1] == 10 {
				log.Warning("Removing newline character from keyphrase input string...")
				opts.AesGcmKeyphrase = string(keyBytes[:len(keyBytes)-1]) // remove line feed
			} else {
				opts.AesGcmKeyphrase = string(keyBytes)
			}
		}
	}

	if opts.AesGcmPasswordToEncrypt != "" { // special flag - encrypt and exit
		if opts.AesGcmKeyphrase == "" {
			log.Fatal("--aes-gcm-password-to-encrypt requires --aes-gcm-keyphrase(-file)")
		}
		fmt.Println(encrypt(opts.AesGcmKeyphrase, opts.AesGcmPasswordToEncrypt))
		os.Exit(0)
	}

	// ad-hoc mode
	if len(opts.AdHocConnString) > 0 || len(opts.AdHocConfig) > 0 {
		if len(opts.AdHocConnString) == 0 || len(opts.AdHocConfig) == 0 {
			log.Fatal("--adhoc-conn-str and --adhoc-config params both need to be specified for Ad-hoc mode to work")
		}
		if len(opts.Config) > 0 {
			log.Fatal("Conflicting flags! --adhoc-conn-str and --config cannot be both set")
		}
		if len(opts.MetricsFolder) > 0 && !CheckFolderExistsAndReadable(opts.MetricsFolder) {
			log.Warningf("--metrics-folder \"%s\" not readable, trying 1st default paths and then Config DB to fetch metric definitions...", opts.MetricsFolder)
		}

		if len(opts.User) > 0 && len(opts.Password) > 0 {
			log.Fatal("Conflicting flags! --adhoc-conn-str and --user/--password cannot be both set")
		}
		if !(opts.AdHocDBType == DBTYPE_PG || opts.AdHocDBType == DBTYPE_PG_CONT) {
			log.Fatalf("--adhoc-dbtype can be of: [ %s (single DB) | %s (all non-template DB-s on an instance) ]. Default: %s", DBTYPE_PG, DBTYPE_PG_CONT, DBTYPE_PG)
		}
		if opts.AdHocUniqueName == "adhoc" {
			log.Warning("In ad-hoc mode: using default unique name 'adhoc' for metrics storage. use --adhoc-name to override.")
		}
		adHocMode = true
	}
	if opts.TestdataDays != 0 || opts.TestdataMultiplier > 0 {
		if len(opts.AdHocConnString) == 0 {
			log.Fatal("Test mode requires --adhoc-conn-str!")
		}
		if opts.TestdataMultiplier == 0 {
			log.Fatal("Test mode requires --testdata-multiplier!")
		}
		if opts.TestdataDays == 0 {
			log.Fatal("Test mode requires --testdata-days!")
		}
	}

	if opts.AddRealDbname != "" {
		addRealDbname = StringToBoolOrFail(opts.AddRealDbname, "--add-real-dbname")
		if opts.RealDbnameField == "" {
			log.Fatal("--real-dbname-field cannot be empty when --add-real-dbname enabled")
		}
	}
	if opts.AddSystemIdentifier != "" {
		addSystemIdentifier = StringToBoolOrFail(opts.AddSystemIdentifier, "--add-system-identifier")
		if opts.SystemIdentifierField == "" {
			log.Fatal("--system-identifier-field cannot be empty when --add-system-identifier enabled")
		}
	}
	if opts.NoHelperFunctions != "" {
		noHelperFunctions = StringToBoolOrFail(opts.NoHelperFunctions, "--no-helper-functions")
	}

	// running in config file based mode?
	if len(opts.Config) > 0 {
		if opts.MetricsFolder == "" && CheckFolderExistsAndReadable(DEFAULT_METRICS_DEFINITION_PATH_PKG) {
			opts.MetricsFolder = DEFAULT_METRICS_DEFINITION_PATH_PKG
			log.Warningf("--metrics-folder path not specified, using %s", opts.MetricsFolder)
		} else if opts.MetricsFolder == "" && CheckFolderExistsAndReadable(DEFAULT_METRICS_DEFINITION_PATH_DOCKER) {
			opts.MetricsFolder = DEFAULT_METRICS_DEFINITION_PATH_DOCKER
			log.Warningf("--metrics-folder path not specified, using %s", opts.MetricsFolder)
		} else {
			if !CheckFolderExistsAndReadable(opts.MetricsFolder) {
				log.Fatalf("Could not read --metrics-folder path %s", opts.MetricsFolder)
			}
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

		fileBasedMetrics = true
	} else if adHocMode && opts.MetricsFolder != "" && CheckFolderExistsAndReadable(opts.MetricsFolder) {
		// don't need the Config DB connection actually for ad-hoc mode if metric definitions are there
		fileBasedMetrics = true
	} else if adHocMode && opts.MetricsFolder == "" && (CheckFolderExistsAndReadable(DEFAULT_METRICS_DEFINITION_PATH_PKG) || CheckFolderExistsAndReadable(DEFAULT_METRICS_DEFINITION_PATH_DOCKER)) {
		if CheckFolderExistsAndReadable(DEFAULT_METRICS_DEFINITION_PATH_PKG) {
			opts.MetricsFolder = DEFAULT_METRICS_DEFINITION_PATH_PKG
		} else if CheckFolderExistsAndReadable(DEFAULT_METRICS_DEFINITION_PATH_DOCKER) {
			opts.MetricsFolder = DEFAULT_METRICS_DEFINITION_PATH_DOCKER
		}
		log.Warningf("--metrics-folder path not specified, using %s", opts.MetricsFolder)
		fileBasedMetrics = true
	} else { // normal "Config DB" mode
		// make sure all PG params are there
		if opts.User == "" {
			opts.User = os.Getenv("USER")
		}
		if opts.Host == "" || opts.Port == "" || opts.Dbname == "" || opts.User == "" {
			fmt.Println("Check config DB parameters")
			return
		}

		_ = InitAndTestConfigStoreConnection(opts.Host, opts.Port, opts.Dbname, opts.User, opts.Password, opts.PgRequireSSL, true)
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

	useConnPooling = StringToBoolOrFail(opts.ConnPooling, "--conn-pooling")

	if pgBouncerNumericCountersStartVersion, err = decimal.NewFromString("1.12"); err != nil {
		log.Fatal("Could not convert string '1.12' to decimal")
	}

	if opts.InternalStatsPort > 0 && !opts.Ping {
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

	promAsyncMode = StringToBoolOrFail(opts.PrometheusAsyncMode, "--prometheus-async-mode")
	if promAsyncMode {
		opts.BatchingDelayMs = 0 // using internal cache, no batching for storage smoothing needed
	}

	control_channels := make(map[string](chan ControlMessage)) // [db1+metric1]=chan
	persist_ch := make(chan []MetricStoreMessage, 10000)
	var buffered_persist_ch chan []MetricStoreMessage

	if !opts.Ping {

		if opts.BatchingDelayMs > 0 && opts.Datastore != DATASTORE_PROMETHEUS {
			buffered_persist_ch = make(chan []MetricStoreMessage, 10000) // "staging area" for metric storage batching, when enabled
			log.Info("starting MetricsBatcher...")
			go MetricsBatcher(DATASTORE_INFLUX, opts.BatchingDelayMs, buffered_persist_ch, persist_ch)
		}

		if opts.Datastore == DATASTORE_GRAPHITE {
			if opts.GraphiteHost == "" || opts.GraphitePort == "" {
				log.Fatal("--graphite-host/port needed!")
			}
			port, _ := strconv.ParseInt(opts.GraphitePort, 10, 32)
			graphite_host = opts.GraphiteHost
			graphite_port = int(port)
			InitGraphiteConnection(graphite_host, graphite_port)
			log.Info("starting GraphitePersister...")
			go MetricsPersister(DATASTORE_GRAPHITE, persist_ch)
		} else if opts.Datastore == DATASTORE_INFLUX {
			// check connection and store connection string
			conn_str, err := InitAndTestInfluxConnection("0", opts.InfluxHost, opts.InfluxPort, opts.InfluxDbname, opts.InfluxUser,
				opts.InfluxPassword, opts.InfluxSSL, opts.InfluxSSLSkipVerify, opts.InfluxRetentionDays)
			if err != nil {
				log.Fatal("Could not initialize InfluxDB", err)
			}
			InfluxConnectStrings[0] = conn_str
			if len(opts.InfluxHost2) > 0 { // same check for Influx host
				if len(opts.InfluxPort2) == 0 {
					log.Fatal("Invalid Influx II connect info")
				}
				conn_str, err = InitAndTestInfluxConnection("1", opts.InfluxHost2, opts.InfluxPort2, opts.InfluxDbname2, opts.InfluxUser2,
					opts.InfluxPassword2, opts.InfluxSSL2, opts.InfluxSSLSkipVerify2, opts.InfluxRetentionDays)
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
			log.Warningf("In JSON output mode. Gathered metrics will be written to \"%s\"...", opts.JsonStorageFile)
			go MetricsPersister(DATASTORE_JSON, persist_ch)
		} else if opts.Datastore == DATASTORE_POSTGRES {
			if len(opts.PGMetricStoreConnStr) == 0 {
				log.Fatal("--datastore=postgres requires --pg-metric-store-conn-str to be set")
			}

			_ = InitAndTestMetricStoreConnection(opts.PGMetricStoreConnStr, true)

			PGSchemaType = CheckIfPGSchemaInitializedOrFail()

			log.Info("starting PostgresPersister...")
			go MetricsPersister(DATASTORE_POSTGRES, persist_ch)

			log.Info("starting UniqueDbnamesListingMaintainer...")
			go UniqueDbnamesListingMaintainer(true)

			if opts.PGRetentionDays > 0 && PGSchemaType != "custom" && opts.TestdataDays == 0 {
				log.Info("starting old Postgres metrics cleanup job...")
				go OldPostgresMetricsDeleter(opts.PGRetentionDays, PGSchemaType)
			}

		} else if opts.Datastore == DATASTORE_PROMETHEUS {
			if opts.TestdataDays != 0 || opts.TestdataMultiplier > 0 {
				log.Fatal("Test data generation mode cannot be used with Prometheus data store")
			}

			if promAsyncMode {
				log.Info("starting Prometheus Cache Persister...")
				go MetricsPersister(DATASTORE_PROMETHEUS, persist_ch)
			}
			go StartPrometheusExporter()
		} else {
			log.Fatal("Unknown datastore. Check the --datastore param")
		}

		_, _ = daemon.SdNotify(false, "READY=1") // Notify systemd, does nothing outside of systemd
	}

	first_loop := true
	mainLoopCount := 0
	var monitored_dbs []MonitoredDatabase
	var last_metrics_refresh_time int64
	var metrics map[string]map[decimal.Decimal]MetricVersionProperties
	var hostLastKnownStatusInRecovery = make(map[string]bool) // isInRecovery
	var metric_config map[string]float64                      // set to host.Metrics or host.MetricsStandby (in case optional config defined and in recovery state

	for { //main loop
		hostsToShutDownDueToRoleChange := make(map[string]bool) // hosts went from master to standby and have "only if master" set
		var control_channel_name_list []string
		gatherers_shut_down := 0

		if time.Now().Unix()-last_metrics_refresh_time > METRIC_DEFINITION_REFRESH_TIME {
			//metrics
			if fileBasedMetrics {
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

		if fileBasedMetrics {
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
					log.Warningf("Could not find a preset metric config named \"%s\", assuming JSON config...", opts.AdHocConfig)
					config, err = jsonTextToMap(opts.AdHocConfig)
					if err != nil {
						log.Fatalf("Could not parse --adhoc-config(%s): %v", opts.AdHocConfig, err)
					}
				}
				md := MonitoredDatabase{DBUniqueName: opts.AdHocUniqueName, DBType: opts.AdHocDBType, Metrics: config, LibPQConnStr: opts.AdHocConnString}
				if opts.AdHocDBType == DBTYPE_PG {
					monitored_dbs = []MonitoredDatabase{md}
				} else {
					resolved, err := ResolveDatabasesFromConfigEntry(md)
					if err != nil {
						if first_loop {
							log.Fatalf("Failed to resolve DBs for ConnStr \"%s\": %s", opts.AdHocConnString, err)
						} else { // keep previously found list
							log.Errorf("Failed to resolve DBs for ConnStr \"%s\": %s", opts.AdHocConnString, err)
						}
					} else {
						monitored_dbs = resolved
					}
				}
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
						log.Fatalf("Could not read/parse monitoring config from path: %s. err: %v", opts.Config, err)
					} else {
						log.Errorf("Could not read/parse monitoring config from path: %s. using last valid config data. err: %v", opts.Config, err)
					}
					time.Sleep(time.Second * time.Duration(opts.ServersRefreshLoopSeconds))
					continue
				}
			}
		} else {
			monitored_dbs, err = GetMonitoredDatabasesFromConfigDB()
			if err != nil {
				if first_loop {
					log.Fatal("could not fetch active hosts - check config!", err)
				} else {
					log.Error("could not fetch active hosts, using last valid config data. err:", err)
					time.Sleep(time.Second * time.Duration(opts.ServersRefreshLoopSeconds))
					continue
				}
			}
		}

		if DoesEmergencyTriggerfileExist() {
			log.Warningf("Emergency pause triggerfile detected at %s, ignoring currently configured DBs", opts.EmergencyPauseTriggerfile)
			monitored_dbs = make([]MonitoredDatabase, 0)
		}

		UpdateMonitoredDBCache(monitored_dbs)

		if lastMonitoredDBsUpdate.IsZero() || lastMonitoredDBsUpdate.Before(time.Now().Add(-1*time.Second*MONITORED_DBS_DATASTORE_SYNC_INTERVAL_SECONDS)) {
			monitored_dbs_copy := make([]MonitoredDatabase, len(monitored_dbs))
			copy(monitored_dbs_copy, monitored_dbs)
			if opts.BatchingDelayMs > 0 {
				go SyncMonitoredDBsToDatastore(monitored_dbs_copy, buffered_persist_ch)
			} else {
				go SyncMonitoredDBsToDatastore(monitored_dbs_copy, persist_ch)
			}
			lastMonitoredDBsUpdate = time.Now()
		}

		if first_loop && (len(monitored_dbs) == 0 || len(metric_def_map) == 0) {
			log.Warningf("host info refreshed, nr. of enabled entries in configuration: %d, nr. of distinct metrics: %d", len(monitored_dbs), len(metric_def_map))
		} else {
			log.Infof("host info refreshed, nr. of enabled entries in configuration: %d, nr. of distinct metrics: %d", len(monitored_dbs), len(metric_def_map))
		}

		if first_loop {
			first_loop = false // only used for failing when 1st config reading fails
		}

		for _, host := range monitored_dbs {
			log.Debugf("processing database: %s, metric config: %v, custom tags: %v, host config: %#v", host.DBUniqueName, host.Metrics, host.CustomTags, host.HostConfig)

			db_unique := host.DBUniqueName
			db_unique_orig := host.DBUniqueNameOrig
			db_type := host.DBType
			metric_config = host.Metrics
			wasInstancePreviouslyDormant := IsDBDormant(db_unique)

			if host.PasswordType == "aes-gcm-256" && len(opts.AesGcmKeyphrase) == 0 && len(opts.AesGcmKeyphraseFile) == 0 {
				// Warn if any encrypted hosts found but no keyphrase given
				log.Warningf("Encrypted password type found for host \"%s\", but no decryption keyphrase specified. Use --aes-gcm-keyphrase or --aes-gcm-keyphrase-file params", db_unique)
			}

			err := InitSqlConnPoolForMonitoredDBIfNil(host)
			if err != nil {
				log.Warningf("Could not init SQL connection pool for %s, retrying on next main loop. Err: %v", db_unique, err)
				continue
			}

			InitPGVersionInfoFetchingLockIfNil(host)

			_, connectFailedSoFar := failedInitialConnectHosts[db_unique]

			if connectFailedSoFar { // idea is not to spwan any runners before we've successfully pinged the DB
				var err error
				var ver DBVersionMapEntry

				if connectFailedSoFar {
					log.Infof("retrying to connect to uninitialized DB \"%s\"...", db_unique)
				} else {
					log.Infof("new host \"%s\" found, checking connectivity...", db_unique)
				}

				ver, err = DBGetPGVersion(db_unique, db_type, true)
				if err != nil {
					log.Errorf("could not start metric gathering for DB \"%s\" due to connection problem: %s", db_unique, err)
					if opts.AdHocConnString != "" {
						log.Errorf("will retry in %ds...", opts.ServersRefreshLoopSeconds)
					}
					failedInitialConnectHosts[db_unique] = true
					continue
				} else {
					log.Infof("Connect OK. [%s] is on version %s (in recovery: %v)", db_unique, ver.VersionStr, ver.IsInRecovery)
					if connectFailedSoFar {
						delete(failedInitialConnectHosts, db_unique)
					}
					if ver.IsInRecovery && host.OnlyIfMaster {
						log.Infof("[%s] not added to monitoring due to 'master only' property", db_unique)
						continue
					}
					metric_config = host.Metrics
					hostLastKnownStatusInRecovery[db_unique] = ver.IsInRecovery
					if ver.IsInRecovery && len(host.MetricsStandby) > 0 {
						metric_config = host.MetricsStandby
					}
				}

				if !opts.Ping && (host.IsSuperuser || (adHocMode && StringToBoolOrFail(opts.AdHocCreateHelpers, "--adhoc-create-helpers"))) && IsPostgresDBType(db_type) && !ver.IsInRecovery {
					if noHelperFunctions {
						log.Infof("[%s] Skipping rollout out helper functions due to the --no-helper-functions flag ...", db_unique)
					} else {
						log.Infof("Trying to create helper functions if missing for \"%s\"...", db_unique)
						_ = TryCreateMetricsFetchingHelpers(db_unique)
					}
				}

				if !(opts.Ping || (opts.Datastore == DATASTORE_PROMETHEUS && !promAsyncMode)) {
					time.Sleep(time.Millisecond * 100) // not to cause a huge load spike when starting the daemon with 100+ monitored DBs
				}
			}

			if IsPostgresDBType(host.DBType) {
				var DBSizeMB int64

				if opts.MinDbSizeMB >= 8 { // an empty DB is a bit less than 8MB
					DBSizeMB, _ = DBGetSizeMB(db_unique) // ignore errors, i.e. only remove from montoring when we're certain it's under the threshold
					if DBSizeMB != 0 {
						if DBSizeMB < opts.MinDbSizeMB {
							log.Infof("[%s] DB will be ignored due to the --min-db-size-mb filter. Current (up to %v cached) DB size = %d MB", db_unique, DB_SIZE_CACHING_INTERVAL, DBSizeMB)
							hostsToShutDownDueToRoleChange[db_unique] = true // for the case when DB size was previosly above the threshold
							SetUndersizedDBState(db_unique, true)
							continue
						} else {
							SetUndersizedDBState(db_unique, false)
						}
					}
				}
				ver, err := DBGetPGVersion(db_unique, host.DBType, false)
				if err == nil { // ok to ignore error, re-tried on next loop
					lastKnownStatusInRecovery := hostLastKnownStatusInRecovery[db_unique]
					if ver.IsInRecovery && host.OnlyIfMaster {
						log.Infof("[%s] to be removed from monitoring due to 'master only' property and status change", db_unique)
						hostsToShutDownDueToRoleChange[db_unique] = true
						SetRecoveryIgnoredDBState(db_unique, true)
						continue
					} else if lastKnownStatusInRecovery != ver.IsInRecovery {
						if ver.IsInRecovery && len(host.MetricsStandby) > 0 {
							log.Debugf("[%s] Switching metrics collection to standby config...", db_unique)
							metric_config = host.MetricsStandby
							hostLastKnownStatusInRecovery[db_unique] = true
						} else {
							log.Debugf("[%s] Using primary config for metrics collection as no standby config defined for host...", db_unique)
							metric_config = host.Metrics
							hostLastKnownStatusInRecovery[db_unique] = false
							SetRecoveryIgnoredDBState(db_unique, false)
						}
					}
				}

				if wasInstancePreviouslyDormant && !IsDBDormant(db_unique) {
					RestoreSqlConnPoolLimitsForPreviouslyDormantDB(db_unique)
				}

				if mainLoopCount == 0 && opts.TryCreateListedExtsIfMissing != "" && !ver.IsInRecovery {
					extsToCreate := strings.Split(opts.TryCreateListedExtsIfMissing, ",")
					extsCreated := TryCreateMissingExtensions(db_unique, extsToCreate, ver.Extensions)
					log.Infof("[%s] %d/%d extensions created based on --try-create-listed-exts-if-missing input %v", db_unique, len(extsCreated), len(extsToCreate), extsCreated)
				}
			}

			if opts.Ping {
				continue // don't launch metric fetching threads
			}

			for metric_name := range metric_config {
				if opts.Datastore == DATASTORE_PROMETHEUS && !promAsyncMode {
					continue // normal (non-async, no background fetching) Prom mode means only per-scrape fetching
				}
				metric := metric_name
				metric_def_ok := false

				if strings.HasPrefix(metric, RECO_PREFIX) {
					metric = RECO_METRIC_NAME
				}
				interval := metric_config[metric]

				if metric == RECO_METRIC_NAME {
					metric_def_ok = true
				} else {
					metric_def_map_lock.RLock()
					_, metric_def_ok = metric_def_map[metric]
					metric_def_map_lock.RUnlock()
				}

				var db_metric string = db_unique + DB_METRIC_JOIN_STR + metric
				_, ch_ok := control_channels[db_metric]

				if metric_def_ok && !ch_ok { // initialize a new per db/per metric control channel
					if interval > 0 {
						host_metric_interval_map[db_metric] = interval
						log.Infof("starting gatherer for [%s:%s] with interval %v s", db_unique, metric, interval)
						control_channels[db_metric] = make(chan ControlMessage, 1)
						PromAsyncCacheInitIfRequired(db_unique, metric)
						if opts.BatchingDelayMs > 0 {
							go MetricGathererLoop(db_unique, db_unique_orig, db_type, metric, metric_config, control_channels[db_metric], buffered_persist_ch)
						} else {
							go MetricGathererLoop(db_unique, db_unique_orig, db_type, metric, metric_config, control_channels[db_metric], persist_ch)
						}
					}
				} else if (!metric_def_ok && ch_ok) || interval <= 0 {
					// metric definition files were recently removed or interval set to zero
					log.Warning("shutting down metric", metric, "for", host.DBUniqueName)
					control_channels[db_metric] <- ControlMessage{Action: GATHERER_STATUS_STOP}
					delete(control_channels, db_metric)
				} else if !metric_def_ok {
					epoch, ok := last_sql_fetch_error.Load(metric)
					if !ok || ((time.Now().Unix() - epoch.(int64)) > 3600) { // complain only 1x per hour
						log.Warningf("metric definition \"%s\" not found for \"%s\"", metric, db_unique)
						last_sql_fetch_error.Store(metric, time.Now().Unix())
					}
				} else {
					// check if interval has changed
					if host_metric_interval_map[db_metric] != interval {
						log.Warning("sending interval update for", db_unique, metric)
						control_channels[db_metric] <- ControlMessage{Action: GATHERER_STATUS_START, Config: metric_config}
						host_metric_interval_map[db_metric] = interval
					}
				}
			}
		}

		atomic.StoreInt32(&mainLoopInitialized, 1) // to hold off scraping until metric fetching runners have been initialized

		if opts.Ping {
			if len(failedInitialConnectHosts) > 0 {
				log.Errorf("Could not reach %d configured DB host out of %d", len(failedInitialConnectHosts), len(monitored_dbs))
				os.Exit(len(failedInitialConnectHosts))
			}
			log.Infof("All configured %d DB hosts were reachable", len(monitored_dbs))
			os.Exit(0)
		}

		if opts.TestdataDays != 0 {
			log.Info("Waiting for all metrics generation goroutines to stop ...")
			time.Sleep(time.Second * 10) // with that time all different metric fetchers should have started
			testDataGenerationModeWG.Wait()
			for {
				pqlen := len(persist_ch)
				if pqlen == 0 {
					if opts.Datastore == DATASTORE_POSTGRES {
						UniqueDbnamesListingMaintainer(false) // refresh Grafana listing table
					}
					log.Warning("All generators have exited and data stored. Exit")
					os.Exit(0)
				}
				log.Infof("Waiting for generated metrics to be stored (%d still in queue) ...", pqlen)
				time.Sleep(time.Second * 1)
			}
		}

		if mainLoopCount == 0 {
			goto MainLoopSleep
		}

		// loop over existing channels and stop workers if DB or metric removed from config
		// or state change makes it uninteresting
		log.Debug("checking if any workers need to be shut down...")
		control_channel_name_list = ControlChannelsMapToList(control_channels)

		for _, db_metric := range control_channel_name_list {
			var currentMetricConfig map[string]float64
			var dbInfo MonitoredDatabase
			var ok, dbRemovedFromConfig bool
			singleMetricDisabled := false
			splits := strings.Split(db_metric, DB_METRIC_JOIN_STR)
			db := splits[0]
			metric := splits[1]
			//log.Debugf("Checking if need to shut down worker for [%s:%s]...", db, metric)

			_, wholeDbShutDownDueToRoleChange := hostsToShutDownDueToRoleChange[db]
			if !wholeDbShutDownDueToRoleChange {
				monitored_db_cache_lock.RLock()
				dbInfo, ok = monitored_db_cache[db]
				monitored_db_cache_lock.RUnlock()
				if !ok { // normal removing of DB from config
					dbRemovedFromConfig = true
					log.Debugf("DB %s removed from config, shutting down all metric worker processes...", db)
				}
			}

			if !(wholeDbShutDownDueToRoleChange || dbRemovedFromConfig) { // maybe some single metric was disabled
				db_pg_version_map_lock.RLock()
				verInfo, ok := db_pg_version_map[db]
				db_pg_version_map_lock.RUnlock()
				if !ok {
					log.Warningf("Could not find PG version info for DB %s, skipping shutdown check of metric worker process for %s", db, metric)
					continue
				}

				if verInfo.IsInRecovery && len(dbInfo.MetricsStandby) > 0 {
					currentMetricConfig = dbInfo.MetricsStandby
				} else {
					currentMetricConfig = dbInfo.Metrics
				}

				interval, isMetricActive := currentMetricConfig[metric]
				if !isMetricActive || interval <= 0 {
					singleMetricDisabled = true
				}
			}

			if wholeDbShutDownDueToRoleChange || dbRemovedFromConfig || singleMetricDisabled {
				log.Infof("shutting down gatherer for [%s:%s] ...", db, metric)
				control_channels[db_metric] <- ControlMessage{Action: GATHERER_STATUS_STOP}
				delete(control_channels, db_metric)
				log.Debugf("control channel for [%s:%s] deleted", db, metric)
				gatherers_shut_down++
				ClearDBUnreachableStateIfAny(db)
				PurgeMetricsFromPromAsyncCacheIfAny(db, metric)
			}
		}

		if gatherers_shut_down > 0 {
			log.Warningf("sent STOP message to %d gatherers (it might take some minutes for them to stop though)", gatherers_shut_down)
		}

		// Destroy conn pools, Prom async cache
		CloseResourcesForRemovedMonitoredDBs(monitored_dbs, prevLoopMonitoredDBs, hostsToShutDownDueToRoleChange)

	MainLoopSleep:
		mainLoopCount++
		prevLoopMonitoredDBs = monitored_dbs

		log.Debugf("main sleeping %ds...", opts.ServersRefreshLoopSeconds)
		time.Sleep(time.Second * time.Duration(opts.ServersRefreshLoopSeconds))
	}

}
