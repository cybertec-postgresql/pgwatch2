## Running the latest version

```docker run -d -p 3000:3000 -p 8080:8080 --name pw2 cybertec/pgwatch2```

or a specific version

```docker run -d -p 3000:3000 -p 8080:8080 --name pw2 cybertec/pgwatch2:x.y.z```

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
