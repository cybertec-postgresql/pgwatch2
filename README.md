# pgwatch2

Flexible self-contained PostgreSQL metrics monitoring/dashboarding solution

# Installing

Software is packaged as Docker so getting started should be easy
```
# fetch and run the latest Docker image, exposing Grafana on port 3000 and administrative web UI on 8080
docker run -d -p 3000:3000 -p 8080:8080 --name pw2 cybertec/pgwatch2
```
After some minutes you could open the ["db-overview"](http://127.0.0.1:3000/dashboard/db/db-overview) dashboard and start
looking at metrics. For defining your own dashboards you need to log in as admin (admin/pgwatch2admin).


For more advanced usecases or for easier problemsolving you can decide to expose all services
```
# run with all ports exposed
docker run -d -p 3000:3000 -p 5432:5432 -p 8083:8083 -p 8086:8086 -p 8080:8080 -p 8088:8088 --name pw2 cybertec/pgwatch2
```
NB! For production usage make sure you also specify listening IPs explicitly (-p IP:host_port:container_port), by default Docker uses 0.0.0.0 (all network devices).

For building the image yourself one needs currently also Go as the metrics gathering daemon is written in it.
```
./build.sh
docker run -d -p 3000:3000 -p 8080:8080 --name pw2 $HASH_FROM_PREV_STEP
```

# Features

* Easy extensibility by defining metrics in pure SQL (thus they could also be from business domain)
* Non-invasive setup, no extensions nor superuser rights required for the base functionality
* DB level configuration of metrics/intervals
* Intuitive metrics presentation using the [Grafana](http://grafana.org/) dashboarding engine
* Optional alerting (Email, Slack, PagerDuty) provided by Grafana


# Components

* pgwatch2 metrics gathering daemon written in Go
* A PostgreSQL database for holding the configuration about which databases and metrics to gather 
* [InfluxDB](https://www.influxdata.com/time-series-platform/influxdb/) Time Series Database for storing metrics
* [Grafana](http://grafana.org/) for dashboarding (point-and-click, a set of predefined dashboards is provided)
* A Web UI for administering the monitored DBs and metrics and for showing some custom metric overviews

# Usage 

* by default the "pgwatch2" configuration database running inside Docker is being monitored so that you can immediately see
  some graphs, but you should add new databases by opening the "admin interface" at 127.0.0.1:8080/dbs or logging into the
  Postgres config DB and inserting into "pgwatch2.monitored_db" table (db - pgwatch2 , default user/pw - postgres/pgwatch2admin)
* one can create new Grafana dashboards (and change settings, create users, alerts, ...) after logging in as "admin" (admin/pgwatch2admin)
* metrics (and their intervals) that are to be gathered can be customized for every database by using a preset config
like "minimal", "basic" or "exhaustive" (monitored_db.preset_config table) or a custom JSON config.
* to add a new metrics  yourself (simple SQL queries returing point-in-time values) head to http://127.0.0.1:8080/metrics.
The queries should always include a "epoch_ns" column and "tag_" prefix can be used for columns that should be tags
(thus indexed) in InfluxDB.
* a list of available metrics together with some instructions is also visible from the "Documentation" dashboard
* some predefine metrics (cpu_load, stat_statements) require installing helper functions (look into "pgwatch2/sql" folder) on monitored DBs 
* for effective graphing you want to familiarize yourself with basic InfluxQL and the non_negative_derivative() function
which is very handy as Postgres statistics are mostly evergrowing counters. Documentation [here](https://docs.influxdata.com/influxdb/latest/query_language/functions/#non-negative-derivative).
* for troubleshooting, logs for the components are visible under http://127.0.0.1:8080/logs/[pgwatch2|postgres|webui|influxdb|grafana] or by logging
into the docker container under /var/logs/supervisor/

# Steps to configure your database for monitoring

* As a base requirement you'll need a login user (non-superuser suggested) for connecting to your server and fetching metrics queries
```
create role pgwatch2 with login password 'secret';
```
* Additionally for extra insights ("Stat statements" dashboard and CPU load) it's also recommended to install the pg_stat_statement
extension and the PL/Python language. The latter one though is usually disabled by DB-as-a-service providers for security reasons.

```
# add pg_stat_statements to your postgresql.conf and restart the server
shared_preload_libraries = 'pg_stat_statements'
```
After restarting the server install the extensions as superuser
```
CREATE EXTENSION pg_stat_statements;
CREATE EXTENSION plpythonu;
```

Now also install the wrapper functions (under superuser role) for enabling "Stat statement" and CPU load info fetching for non-superusers
```
psql -h mydb.com -U superuser -f pgwatch2/sql/metrics_fetching_helpers/stat_statements_wrapper.sql mydb
psql -h mydb.com -U superuser -f pgwatch2/sql/metrics_fetching_helpers/cpu_load_plpythonu.sql mydb
```

# Technical details

* Dynamic management of monitored databases, metrics and their intervals - no need to restart/redeploy
* Safety
  - only one concurrent query per monitored database is allowed so side-effects shoud be minimal
  - configurable statement timeouts
  - SSL connections support for safe over-the-internet monitoring
  - Optional authentication for the Web UI and Grafana (by default freely accessible!)
* Backup script (take_backup.sh) provided for taking snapshots of the whole setup. To make it easier (run outside the container)
one should to expose ports 5432 (Postgres) and 8088 (InfluxDB backup protocol) at least for the loopback address.

# Screenshot of the "DB overview" dashboard
!["DB overview" dashboard](https://github.com/cybertec-postgresql/pgwatch2/raw/master/screenshots/overview.png)
