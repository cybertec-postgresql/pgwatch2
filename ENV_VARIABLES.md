# Available env. variables by components

NB! Some variables influence multiple components. Command line parameters override env. variables (when doing custom deployments).

## Docker image specific

- **NOTESTDB** When set, the config DB won't be added to monitoring as "test". Default: -
- **PW2_PG_SCHEMA_TYPE** Enables to choose different metric storage models for the "pgwatch2-postgres" image - [metric-time|metric-dbname-time]. Default: metric-time

## Gatherer daemon

- **PW2_PGHOST** Config DB host. Default: localhost
- **PW2_PGPORT** Config DB port. Default: 5432
- **PW2_PGDATABASE** Config DB name. Default: pgwatch2
- **PW2_PGUSER** Config DB user. Default: pgwatch2
- **PW2_PGPASSWORD** Config DB password. Default: pgwatch2admin
- **PW2_PGSSL** Config DB SSL connection only. Default: False
- **PW2_GROUP** Logical grouping/sharding key to monitor a subset of configured hosts. Default: -
- **PW2_DATASTORE** Backend for metric storage - [influx|postgres|prometheus|graphite|json]. Default: influx
- **PW2_VERBOSE** Logging vebosity. By default warning and errors are logged. Use [-v|-vv] to include [info|debug]. Default: -
- **PW2_PG_METRIC_STORE_CONN_STR** Postgres metric store connection string. Required when PW2_DATASTORE=postgres. Default: -
- **PW2_PG_RETENTION_DAYS** Effective when PW2_DATASTORE=postgres. Default: 14
- **PW2_IHOST** InfluxDB host. Default: localhost
- **PW2_IPORT** InfluxDB port. Default: 8086
- **PW2_IUSER** InfluxDB username. Default: root
- **PW2_IPASSWORD** InfluxDB password. Default: root
- **PW2_IDATABASE** InfluxDB database. Default: pgwatch2
- **PW2_ISSL** Use SSL for InfluxDB. Default: False
- **PW2_ISSL_SKIP_VERIFY** Skip SSL cert validation. Allows self-signed certs. Default: true
- **PW2_IHOST2** Secondary InfluxDB host. Default: localhost
- **PW2_IPORT2** Secondary InfluxDB port. Default: 8086
- **PW2_IUSER2** Secondary InfluxDB username. Default: root
- **PW2_IPASSWORD2** Secondary InfluxDB password. Default: root
- **PW2_IDATABASE2** Secondary InfluxDB database. Default: pgwatch2
- **PW2_ISSL2** Use SSL for Secondary InfluxDB. Default: False
- **PW2_ISSL_SKIP_VERIFY2** Skip SSL cert validation. Allows self-signed certs. Default: true
- **PW2_IRETENTIONDAYS** Influx metrics retention period in days. Default: 30
- **PW2_IRETENTIONNAME** Influx retention policy name. Default: pgwatch_def_ret
- **PW2_GRAPHITEHOST** Graphite host. Default: -
- **PW2_GRAPHITEPORT** Graphite port. Default: -
- **PW2_CONFIG** File mode. File or folder of YAML (.yaml/.yml) files containing info on which DBs to monitor and where to store metrics
- **PW2_METRICS_FOLDER** File mode. Folder of metrics definitions
- **PW2_BATCHING_MAX_DELAY_MS** Max milliseconds to wait for a batched metrics flush. Default: 250
- **PW2_ADHOC_CONN_STR** Ad-hoc mode. Monitor a single Postgres DB specified by a standard Libpq connection string
- **PW2_ADHOC_CONFIG** Ad-hoc mode. A preset config name or a custom JSON config. Default: exhaustive
- **PW2_ADHOC_CREATE_HELPERS** Ad-hoc mode. Try to auto-create helpers. Needs superuser to succeed. Default: false
- **PW2_ADHOC_NAME** Ad-hoc mode. Unique 'dbname' for Influx. Default: adhoc
- **PW2_INTERNAL_STATS_PORT** Port for inquiring monitoring status in JSON format. Default: 8081
- **PW2_CONN_POOLING** Enable re-use of metrics fetching connections. "off" means reconnect every time. Default: off
- **PW2_AES_GCM_KEYPHRASE** Keyphrase for encryption/decpyption of connect string passwords.
- **PW2_AES_GCM_KEYPHRASE_FILE** File containing a keyphrase for encryption/decpyption of connect string passwords.
- **PW2_AES_GCM_PASSWORD_TO_ENCRYPT** A special mode, returns the encrypted plain-text string and quits. Keyphrase(file) must be set
- **PW2_TESTDATA_DAYS** For how many days to generate data. Requires Ad-hoc params to be set also.
- **PW2_TESTDATA_MULTIPLIER** For how many hosts to generate data. Requires Ad-hoc params to be set also.
- **PW2_PROMETHEUS_PORT** Prometheus port. Effective with --datastore=prometheus. Default: 9187
- **PW2_PROMETHEUS_LISTEN_ADDR** Network interface to listen on". Default: "0.0.0.0"


## Web UI

- **PW2_WEBHOST** Network interface to listen on. Default: 0.0.0.0
- **PW2_WEBPORT** Port. Default: 8080
- **PW2_WEBSSL** Use HTTPS with self-signed certificates, Default: False
- **PW2_WEBCERT** Enables use of own certificates for custom deployments. Default: '/pgwatch2/persistent-config/self-signed-ssl.pem'
- **PW2_WEBKEY** Enables use of own certificates for custom deployments. Default: '/pgwatch2/persistent-config/self-signed-ssl.key'
- **PW2_WEBCERTCHAIN** Path to certificate chain file for custom deployments. Default: -
- **PW2_WEBNOANONYMOUS** Require user/password to edit data. Default: False
- **PW2_WEBUSER** Admin login. Default: pgwatch2
- **PW2_WEBPASSWORD** Admin password. Default: pgwatch2admin
- **PW2_WEBNOCOMPONENTLOGS** Don't expose Docker component logs. Default: False
- **PW2_VERBOSE** Logging vebosity. By default warning and errors are logged. Use [-v|-vv] to include [info|debug]. Default: -
- **PW2_PGHOST** Config DB host. Default: localhost
- **PW2_PGPORT** Config DB port. Default: 5432
- **PW2_PGDATABASE** Config DB name. Default: pgwatch2
- **PW2_PGUSER** Config DB user. Default: pgwatch2
- **PW2_PGPASSWORD** Config DB password. Default: pgwatch2admin
- **PW2_PGSSL** Config DB SSL connection only. Default: False
- **PW2_IHOST** InfluxDB host. Default: localhost
- **PW2_IPORT** InfluxDB port. Default: 8086
- **PW2_IUSER** InfluxDB username. Default: root
- **PW2_IPASSWORD** InfluxDB password. Default: root
- **PW2_IDATABASE** InfluxDB database. Default: pgwatch2
- **PW2_ISSL** Use SSL for InfluxDB. Default: False
- **PW2_GRAFANA_BASEURL** For linking to Grafana "Query details" dashboard from "Stat_stmt. overview". Default: http://0.0.0.0:3000
- **PW2_AES_GCM_KEYPHRASE** Keyphrase for encryption/decpyption of connect string passwords.
- **PW2_AES_GCM_KEYPHRASE_FILE** File containing a keyphrase for encryption/decpyption of connect string passwords.
- **PW2_DATASTORE** Backend for metric storage - [influx|postgres|graphite]. Default: influx
- **PW2_PG_METRIC_STORE_CONN_STR** Postgres metric store connection string. Required when PW2_DATASTORE=postgres. Default: -


## Grafana

- **PW2_GRAFANANOANONYMOUS** Can be set to require login even for viewing dashboards. Default: -
- **PW2_GRAFANAUSER** Administrative user. Default: admin
- **PW2_GRAFANAPASSWORD** Administrative user password. Default: pgwatch2admin
- **PW2_GRAFANASSL** Use SSL. Default: -
- **PW2_GRAFANA_BASEURL** For linking to Grafana "Query details" dashboard from "Stat_stmt. overview". Default: http://0.0.0.0:3000


## InfluxDB

None. NB! InfluxDB built into the pgwatch2 Docker image provides no security (setting up a custom user/password requires
quite some steps), so if this is a concern, the according ports 8086/8088 should just not be exposed, or a custom setup.
