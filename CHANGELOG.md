## Running the latest version

```
docker run -d -p 3000:3000 -p 8080:8080 --name pw2 cybertec/pgwatch2    # InfluxDB version
# OR
docker run -d -p 3000:3000 -p 8080:8080 --name pw2 cybertec/pgwatch2-postgres   # Postgres version
```

or a specific version

```docker run -d -p 3000:3000 -p 8080:8080 --name pw2 cybertec/pgwatch2:x.y.z```


## v1.6.2 [2019-09-27]

* Gatherer improvement - support password/cert authentication for Patroni and etcd
* Gatherer improvement - make pgwatch2 "superuser" aware. Superusers don't need helpers any more for non-Python metrics
* Gatherer fix - in YAML mode statement timeout config file sample didn't match the actual parsing key
* Metrics store fix - correct "metric-dbname-time" model weekly partition creation
* Metrics store improvement - gatherer would not always recover from PG storage failures and restart was needed
* Gatherer improvement - make SystemD service template to re-start on failure
* Gatherer improvement - remove built-in statement timeout override for bloat queries
* Gatherer improvement - always set statement timeout explicitly before any metric queries to avoid a corner case
* Dashboards - new "Postgres Version Overview" dash
* Dashboards - new "Stat Statements SQL Search" dash for finding execution stats for matching SQL texts
* Dashboards - by default filter out pgwatch2 generated metric fetching queries in Stat Statements Top 
* Dashboards - Health-check description updates and minor corrections
* Metrics - add 'wal_size' (10+) to 'exhaustive' preset
* Metrics - replace accurate "pgstattuple" based bloat info gathering with SQL based estimates in preset configs
* Metrics - correct older (9.0/9.1) "backends" and "kpi" metrics
* Metrics - add Autovacuum info to "settings" and "table_stats" + display on PG "health-check" dash
* Metrics - "kpi" was failing on replicas for some PG versions
* Docker - fix case where setting PW2_GRAFANASSL=0 still enabled SSL
* Docker - make "Health-check" the default dashboard / splash screen
* Docker component update: Influx 1.7.8, Grafana 6.3.6, Go 1.12.10


## v1.6.1 [2019-08-13]

* Config DB fix - allow 'patroni-continuous-discovery' DB type available in YAML mode
* Web UI fix - adding/updating new metrics was broken
* Gatherer fix - correct PG version display, v10.10 was displayed as 10.1
* Gatherer improvement - add --version option to display build Git version
* Metrics DB improvement - metric-dbname-time Postgres storage model using weekly partitions instead of monthly now
* Metrics and metrics DB - add "psql" rollout scripts
* Metrics - add n_live_tup, n_dead_tup to 'table_stats'
* Web UI improvement - replace "psycopg2" dependency with "psycopg2-binary"
* Web UI improvement - don't try to check connection for Patroni dbtype
* Web UI improvement - some sanity checks on adding preset configs
* Dashboards - add unused repl. slots to the Alert Template
* Docker - Dockerfiles not directly dependant on Git now but --build-args + Bash build helper scripts
* Docker component update: Influx 1.7.7, Grafana 6.2.5, Go 1.12.7



## v1.6.0 [2019-06-19]

* Gatherer feature - add support for Prometheus scraping
* Gatherer feature - Patroni (etcd, Zookeeper, Consul) support (non-password access)
* Gatherer feature - add a flag to monitor DB-s only when they are acting as master / primary
* Gatherer feature - a flag (add-system-identifier / system-identifier-field) to save the "system identifier" with each metric (10+)
* Gatherer fix - handle zeroing of running metric intervals
* Gatherer fix - let the PG driver use .pgpass if no password specified in host settings
* Packaging - Goreleaser support to build DEB, RPM, tarball
* Gatherer improvement - don't start per metric gatherers until connect check OK
* Gatherer improvement -revert persistance maxBatchSize from 5k back to 1k points
* Gatherer improvement - allow partial InfluxDB writes
* Gatherer improvement - support SCRAM-SHA-256 password authentication via Go driver update
* Gatherer improvement - support LibPQ style connection strings in YAML configs
* Gatherer improvement - don't try to auto-create helpers on standbys
* Dashboards - support for Grafana v6 plus minor updates for most dashboards. v5 dashboards will not get updates any more!
* Dashboards - "Health-check" overhaul. PG ver, uptime, transaction wraparound, longest autovacuum and other infos
* Dashboards - a template for alerting with preset thresholds for couple of most important metrics. For PG backend only.
* Dashboards - links going out from "Top stms/table/sproc" dashboards now preserve the selected timerange
* Metrics improvement - skip index_stats gathering for locked indexes
* Metrics - support upcoming PG v12
* Metrics - new "settings" metric based on pg_settings + according panel to "Change events"
* Metrics - capture "server restarted" events when "db_stats" metric enabled (visualized on "Change events" dash)
* Metrics - increase intervals for index/table stats
* Metrics - add a sample bash script to push arbitrary metrics to the pgwatch2 metrics DB externally
* Metrics - add "system identifier" to "wal" to enable auto-grouping of cluster members
* Metrics PG storage - support very long database names also in metric-dbname-time mode. Thanks @henriavelabarbe!
* Config store - add a schema versioning table so that next version schema change diffs could be auto-applied 
* Web UI - external component update + according HTML / CSS changes: Bootstrap 3 -> 4, jQuery 3.1 -> 3.4
* Docker components update -  Grafana 6.2.4, Go 1.12.6, Influx 1.7.6

NB! When migrating old "config DB" based setups, all previous schema migration diffs with bigger version numbers need to be
applied first from the "pgwatch2/sql/config_store/migrations/" folder.

## v1.5.1 [2019-02-11]

* Gatherer fix - 'continous discovery' worked only in YAML mode
* Metrics fix - pre 9.2 'backends' SQL was incorrect
* Gatherer improvement - 'auto-create helpers' (if "checked") applied to all found DBs now
* Gatherer improvement - "funny" DB names (spaces etc) can be now monitored also with Postgres as storage DB
* Gatherer improvement - issue a warning instead of crash when AES encrypted password does not match required format
* Gatherer improvement - add ability to generate encrypted passwords e.g. for YAML usage, via --aes-gcm-password-to-encrypt param
* Web UI improvement - allow changing password type from plain to AES and vice-versa without re-entering password
* Metrics change - restrict metric names to alphanumerics and underscores. All built-in metrics were already obeying that practice
* Metrics improvement - add a 'create extension if not exists pg_stat_statements' to the get_stat_statements helper SQL
* Docker image with Postgres metrics storage - possible to enable also the "metric-dbname-time" storage model via PW2_PG_SCHEMA_TYPE env. var
* Readme - explanations to available "DB type" options

NB! When migrating old "config DB" based setups, all previous schema migration diffs with bigger version numbers need to be
applied first from the "pgwatch2/sql/config_store/migrations/" folder.

## v1.5.0 [2019-01-24]

* New feature - Support Postgres as metrics storage DB (--pg-schema-type, --pg-metric-store-conn-str, --pg-retention-days)
* New feature - password encryption/decryption with AES-GCM-256 (Gatherer + Web UI)
* New feature - 'verify-ca' and 'verify-full' SSLMODE support (Gatherer + Web UI)
* New feature - Test data generation. New params --testdata-days and --testdata-multiplier (host count)
* New feature - standby-only or master-only metrics (less errors in PG and pgwatch2 logs)
* Gatherer improvement - SystemD support + service file. Thanks @slardiere!
* Gatherer improvement - less error messages when monitored DB or metrics store is down
* Gatherer improvement - disable "connection pooling" by default 
* Gatherer improvement - collector logic refactoring, less message passing 
* Gatherer improvement - correct "complain only 1x per hour about missing metric definitions"
* Gatherer improvement - new flag for "ad-hoc" mode to control auto-creation of helpers
* New metrics - "wal_receiver" (standby-only), "archiver" (over pg_stat_archiver)
* Metrics improvement - no "public" schema specified in metrics anymore so helpers/extensions can reside anywhere
* Metrics improvement - no explicit grants to "public" for helpers, only to pgwatch2 role
* Metrics - removing DB size from "db_stats" into own "db_size" as it's apparently slow on some FS
* Metrics - new "backup_duration_s" field for "db_stats"
* Metrics - "pg_" removed from "pg_stat_ssl" and "pg_stat_database_conflicts" due to problems with Postgres backend
* Metrics - slight increases to all preset config intervals to be on the conservative side
* Metrics - more efficient "psutil_cpu" helper and useful also with non-persistent sessions
* Dashboard improvement - explicit "agg_interval" variable for most PG overview dashboards as a Grafana workaround
* Web UI improvement - index (default) page set to the "Monitored DBs" page
* Docker - "daemon" image runs now also without any parameters 
* Docker - use "tsi1" disk-based index instead of "inmem" for Influx as it's safer for high-cardinality setups
* Docker - new image with Postgres for metrics storage (cybertec/pgwatch2-postgres-storage)  
* Docker component update - InfluxDB 1.7.3, Grafana 5.4.3, Go 1.11.4

NB! When migrating old "config DB" based setups, v1.5.0* schema migration
diffs need to be applied first from the "pgwatch2/sql/migrations/" folder.


## v1.4.5 [2018-11-06]

* Metrics fix - KPI for 9.6 corrected
* Gatherer improvement - complain only 1x per hour about missing metric definitions
* Gatherer improvement - re-cycle config DB connections the same way as for monitored DBs
* Gatherer feature - introduce parallel metric fetching per DB, max. 2 queries (hardcoded)
* Gatherer feature - default timeout for built-in bloat metrix set to 30min to run through for 100GB+ tables
* New dash - "Healt-check". Main KPI-s as "single stat" panels with links to according graphs
* New dash - "Index overview". Also supporting "index_stats" metric changes
* New dash - "Tables top". Top-N by size/growth/IUD
* Dashboards - "Replication lag" now has a "dbname" filter like most other dashboards + 2 new panels
* New metric - "archiver" based on pg_stat_archiver to detect WAL shipping issues
* New metric/helper - "wal_size" based on pg_ls_waldir() to detect accumulating WAL folder. PG 10+ 
* Docker component update - InfluxDB 1.6.4 and Grafana 5.3.2


## v1.4.1 [2018-10-05]

* Metrics fix - PG10+ 'backends.waiting' column filter was including also non-blocked states
* Dashboard fix - some "Checkpointer/Bgwriter" panels didn't respect "dbname"
* Gatherer feature - allow self-signed InfluxDB SSL certs by default in the gatherer
* Gatherer feature - enable storing gathered metrics to a JSON file with --datastore=json + --json-storage-file=somefile. Allows testing metric gathering and also possibly some data integrations with custom monitoring systems
* Gatherer improvment - better error message on stats interface port collision
* Metrics - casting some fields explicitly to int8
* Metrics - Added XMIN horizon to replication_slots/stat_activity metrics
* Dashboard improvement - increase most aggregation intervals to 5min (was 2m) + some small usability improvements
* Docker component update - Golang 1.11.1, InfluxDB 1.6.3 and Grafana 5.2.4


## v1.4.0 [2018-08-29]

* Feature - "config file based operation". Now one can run pgwatch2 without the config DB using YAML configs, making automatization easier. See README or help output on --metrics-folder/--config params
* Feature - "Ad hoc" mode. For test/ad hoc purposes the gatherer can now be run from command line, given a JDBC connect string. See README or --adhoc-conn-str param
* Feature - "continous discovery". The gatherer daemon can now periodically scan for new DBs on the cluster and monitor them automatically
* Feature - "custom tags". Now users can add any data (e.g. env. flags/app ID's) to be stored for all metric points as tags in InfluxDB
* Feature -  a stats/health interface outputting JSON on internal metric counters for the gatherer. Runs on port 8081 by default, use --internal-stats-port to change
* Feature -  "Group" field added for monitored DBs. Enables logical separation and thus running many gatherers on one config DB (sharding)
* Improvement - batching of InfluxDB requests. Huge latency wins over slower connections. Default batching delay is 250ms (changeable)
* Improvement - gatherer daemon now supports < 1s gathering intervals for some extreme use cases
* Improvement - connection pooling on monitored DBs (with 30min recycling). Can be disabled via the --conn-pooling param
* Improvement - set "pgwatch2" as application name on all DB connections for better visibility
* Improvement - InfluxDB retention policy / duration made configurable on command line
* Dashboards - new "DB overview Developer / Unprivileged" dashboard together with an according preset metrics set
* Dashboards - new "System Stats" dashboard together with according helpers / metrics. "psutil" Python package required
* Dashboards - new "Checkpointer/Bgwriter/Block IO Stats" dashboard
* Dashboards - "DB overview" dashboard simplified a bit to be more beginner friendly
* Dashboards - lots of minor corrections e.g. for "Single query details", "Replication"
* Metrics - new metrics "replication_slots", "psutil*" (to take advantage of Python's "psutil" package for OS/system metrics)
* Fix - pg_stat_statements wrapper now compatible with 9.2/9.3
* Fix - make server config change tracking work for PG <9.5
* Fix - correct auto-adding of all DBs in a cluster via Web UI
* Fix - Web UI --pg-require-ssl/--verbose param handling made more robust for env. usage
* Docker - expose the new gather internal statistics port 8081
* Docker - reduce default metrics retention from 90d to 30d
* Docker - Grafana updated to 5.2.2
* Docker - Influx updated to 1.6.1

NB! To migrate from older installations it's also needed to execute v1.4.0 SQL-s from the "pgwatch2/sql/datastore_setup/migrations" folder on the config DB. 

## v1.3.7 [2018-06-10]

* Fix - Openshift/nonroot Docker image was failing on container re-launch due to Postgres SSL false handling
* Fix - setting Grafana SSL via env working now again 
* Dashboards - new "Global Overview" dash added for aggregates over all or a set of DBs
* Dashboards - new "Top Sprocs" dash added. Similar to "State Statements Top"
* Dashboards - "Overview" dash "avg. query runtime" more accurate now as pgwatch2 queries are excluded from calculation
* Improvement - stat_statements_calls doesn't need superuser anymore
* Metrics - increase default metric intervals for "multipliable" data i.e. metrics that grow proportional to the amount of objects
* Metrics - added total_time to stat_statements_calls for fast (approximate) avg. query runtime calculation
* Docker - SSL keys are now not re-generated on evey launch        
* Web UI - better error handling when Influx DB is not there  
* InfluxDB 1.5.1 -> 1.5.3
* Grafana 5.0.4 -> 5.1.3


## v1.3.6 [2018-04-12]

* Admin UI fix - remove confusing error messages shown on existing connection string updates
* Improvement - stat_statements_calls doesn't need superuser anymore
* Security improvement - only showing pg_stat_activity info on the taget DB
* Metric fix - helper (for superuser auto-create) for bloat was missing
* Gatherer - fix "auto-create" of metric fetching helpers (effective when "Is superuser?" checked on Admin page)
* "Overview" dashboard - minor adjustments
* InfluxDB 1.5.0 -> 1.5.1


## v1.3.5 [2018-04-02]

* Fix - When using volumes, Postgres Bootstrap was correctly done only for volumes created with "docker volume"
* Fix - Gatherer was always re-logging metric interval change events
* Improvement - 'Stat statements top' dasboard compatibility for older Influx versions (@dankasak)
* Metric improvement - "backends" now has separate parallel query workers counter for PG10+
* Metric/dash improvement - "Sproc details" now based on fully qualified procedure names
* Minor dashboard improvements - "Table details" and "Overview" adjusted for less jumpy graphs on default settings. NB! If migrating an existing setup it is highly recommended to re-import the following dashboards: "Table details", "Overview", "Sproc details"
* Web UI Improvement - showing a warning on "DBs" page if changing the connect string but can't actually connect using it
* README improvements - info on "track_io_timing", component diagram added, new screenshots, project background
* Logging improvement - in some case root cause errors were masked in logs. Better "empty metric SQL" messages
* Logging improvement - remove duplicate event times and milliseconds
* Openshift template - added missing PW2_IRETENTIONDAYS to env vars
* InfluxDB 1.5.0
* Grafana 5.0.4 - old v4 dashboards are now in a separate folder (./grafana_dashboards/v4)
* Go 1.10.1

## v1.3.0 [2018-01-26]

* Dockerfile/image running as "non-root" user, suitable for example for OpenShift deployments
* Docker VOLUME-s added to Postgres, Grafana, InfluxDB data directories and pgwatch2 persistent config
* Added Dockerfiles for deploying components separately. See the "docker" folder for details
* Grafana security - possible to control anon. access and admin user/passord via env. variables
* New dashboard - AWS CloudWatch overview. One can now easily monitor/alert on on-prem and cloud DBs
* New dashboard and datasource type for PgBouncer stats. Visualizes pgbouncer "SHOW STATS" commands. NB! Requires config DB schema
 change for existing setups, DB-diff file [here](https://github.com/cybertec-postgresql/pgwatch2/blob/master/pgwatch2/sql/datastore_setup/migrations/v1.3.0_monitored_db_dbtype.sql)
* New dashboard for "Top N" time consuming/frequent/slowest/IO-hungry queries added. Base on pg_stat_statements info. NB! When no
 SQL info should be leaked, dashboard should be deleted after image start as it shows (parametrized) queries!
* New dashboard - "Biggest relations treemap". Helps to visually detect biggest tables/indexes
* Dashboard chage to "Single query details" - add IO time percentage graph of total time to determine if query is IO or CPU bound. Also
 showing SQL for the query
* Gatherer daemon - InfluxDB HA support added, i.e. writing metrics to 2 independent DBs. Can be also used for load balancing
* Gatherer daemon - a ringbuffer of max 100k metrics datapoints introduced (i.e. 2GB of RAM) if metric storage is gone.
 Previously metrics were gather till things blew up
* Gatherer daemon - improved the startup sequence, no load spikes anymore in case of 50+ monitored DBs
* Gatherer daemon - "--iretentiondays" param added to specify InfluxDB retention period (90d default)
* Improved Web UI - nicer errors and providing partial functionality when Postgres or InfluxDB is not available
* Improved Web UI - not showing the "Log out" btn if no authentication was enabled (the default)
* Improved Web UI - new flag ---no-component-logs added to not expose error logs for all the components running in Docker
* Improved Web UI - respecting the --pg-require-ssl param now to force SSL connections to config DB
* README improvements - a new section on custom deployments and some other minor additions
* "Change detection" dashboard/metric improvement - the monitoring DB role is not expected to be superuser anymore
* "Change detection" improvement - showing change event annotations only for the selected DB now
* Improvement - Postgres version for monitored hosts cached for 2 minutes now
* Improvement - Docker image size reduced 20%
* Fix - corrections for "backend" metrics gathering wrapper functions

## v1.2.3 [2017-12-13]

* Fix for Web UI/Grafana HTTPS mode (outgoing links/logos are now also HTTPS)
* Fix for Docker image Go gatherer - config DB env parameters (PW2_PG*) are now fully respected
* Fix for the "backend" metric - some fields were "null" when using non-superuser. Now there's a
 wrapper - thanks @jimgolfgti!
* Improvement - table_stats metric skips now over exclusively locked tables
* Improvement - various "Table details" dashboard adjustments (e.g. TOAST/index size info) and according table_stats/index_stats
 metric adjustments (new full_table_name tag used for searching to counter duplicate table names)
* InfluxDB 1.4.2
* Grafana 4.6.2

## v1.2.2 [2017-11-05]

* Fix for "panic: runtime error: index out of range" when last table/sproc/index of DB was deleted
* Fix for "max key length exceeded" errors. Stored query texts limited to 16000 chars.
* InfluxDB 1.3.7
* Grafana 4.6.1
* Go 1.9.2

## v1.2.1 [2017-10-17]

* Fix for "max key length exceeded" errors. Stored query texts limited to 65000 chars.
* InfluxDB 1.3.6
* Grafana 4.5.2

## v1.2.0 [2017-09-19]

* Deletion of InfluxDB data from the Web UI now possible
* Adding of all databases from a host now possible when leaving "DB name" empty
* All components (Grafana, Postgres, InfluxDB/Graphite) made externally pluggable e.g. you can use your
existing InfluxDB to store and access metrics. See README for details
* Fixed login page (no new window popup)
* Not exposing port 8083 anymore as InfluxDB UI was deprecated. Use Chronograf for ad hoc queries from now on
* Better validations and tooltips for the monitored hosts ("/dbs") page in Web UI
* An env. flag not to create the "test" database when launching a pgwatch2 container (-e NOTESTDB=1)
* Make config store DB (Postgres) UTF-8 encoded to avoid problems with non-ascii Grafana dashboard names
* Faster Docker builds when developing, more static parts come first now
* Filtering additionally also on "dbname" besides "queryid" for the "Single query" dashboard
* Corrections and better documentation for the backup/restore script
* InfluxDB 1.3.5 - lots of bugfixes and perf improvements
* Grafana 4.5.1 - query inspection, better query builders and data tables

## v1.1.0 [2017-06-05]

* Support for Graphite as metric storing database
* SSL support for Grafana and the Web UI
* Support for the upcoming PostgreSQL version 10
* Support for beta/devel versions of Postgres as well as EDB Postgres Advanced Server
* New "change detection" feature and according dashboard
* New stored procedure details dashboard called "Sproc details"
* New approximate table bloat monitoring metric and panel for "DB Overview" dashboard (9.5+)
* New "Queries per Second" panel (QPS label) and according metric stat_statements_calls
* Automatic creation of metric fetching helpers for ssuperusers
* Building the Go daemon with Docker now
* Grafana 4.3.0 - histograms and heatmaps now possible

## v1.0.5 [2017-04-10]

* Couple of smaller "Overview" dashboard corrections
* InfluxDB update from 1.2.0 to 1.2.2
* Grafana update from 4.1.2 to 4.2.0

## v1.0.0 [2017-01-30]

* Initial release
