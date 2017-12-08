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
NB! If you don't want to add the "test" database (the pgwatch2 configuration db) for monitoring set the NOTESTDB=1 env parameter when launching the image.


For more advanced usecases or for easier problemsolving you can decide to expose all services
```
# run with all ports exposed
docker run -d -p 3000:3000 -p 5432:5432 -p 8086:8086 -p 8080:8080 -p 8088:8088 --name pw2 cybertec/pgwatch2
```
NB! For production usage make sure you also specify listening IPs explicitly (-p IP:host_port:container_port), by default Docker uses 0.0.0.0 (all network devices).

For custom options, more security, or specific component versions one could easily build the image themselves, just Docker needed:
```
docker build .
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

NB! All component can be also used separately, thus you can descide to make use of an already existing installation of Postgres, 
Grafana or InfluxDB and run the pgwatch2 image for example only with the metrics gatherer and the configuration Web UI.
These external installations must be accessible from within the Docker though.

### To use an existing Postgres DB

Create a new pgwatch2 DB, preferrably also an accroding role who owns it. Then roll out the schema (pgwatch2/sql/datastore_setup/config_store.sql)
and set the following parameters when running the image: PW2_PGHOST, PW2_PGPORT, PW2_PGDATABASE, PW2_PGUSER, PW2_PGPASSWORD, PW2_PGSSL (optional).

### To use an existing Grafana installation

Load the pgwatch2 dashboards from *grafana_dashboard* folder if needed (one can totally define their own) and set the following paramater: PW2_GRAFANA_BASEURL.
This parameter only provides correct links to Grafana dashboards from the Web UI. Grafana is the most loosely coupled component for pgwatch2
and basically doesn't have to be used at all. One can make use of the gathered metrics directly over the Influx (or Graphite) API-s.

### To use an existing InfluxDB installation

Set the following env variables: PW2_IHOST, PW2_IPORT, PW2_IDATABASE, PW2_IUSER, PW2_IPASSWORD, PW2_ISSL (optional)

### To use an existing Graphite installation

One can also store the metrics in Graphite instead of InfluxDB (no predefined pgwatch2 dashboards for Graphite though).
Following parameters needs to be set then: PW2_DATASTORE=graphite, PW2_GRAPHITEHOST, PW2_GRAPHITEPORT



# Usage 

* by default the "pgwatch2" configuration database running inside Docker is being monitored so that you can immediately see
  some graphs, but you should add new databases by opening the "admin interface" at 127.0.0.1:8080/dbs or logging into the
  Postgres config DB and inserting into "pgwatch2.monitored_db" table (db - pgwatch2 , default user/pw - pgwatch2/pgwatch2admin).
  Note that it can take up to 2min before you see any metrics for newly inserted databases.
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
* Define the helper function to enable the monitoring of sessions, blocking locks, etc by the `pgwatch2` login defined above, if using a superuser login (not recommended) you can skip this step, just ensure that you check the `Is superuser?` check box when configuring Databases
```
psql -h mydb.com -U superuser -f pgwatch2/sql/metric_fetching_helpers/stat_activity_wrapper.sql mydb
```

* Additionally for extra insights ("Stat statements" dashboard and CPU load) it's also recommended to install the pg_stat_statement
extension (Postgres 9.4+ needed to be useful for pgwatch2) and the PL/Python language. The latter one though is usually disabled by DB-as-a-service providers for security reasons.

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
psql -h mydb.com -U superuser -f pgwatch2/sql/metric_fetching_helpers/stat_statements_wrapper.sql mydb
psql -h mydb.com -U superuser -f pgwatch2/sql/metric_fetching_helpers/cpu_load_plpythonu.sql mydb
```

# Screenshot of the "DB overview" dashboard
!["DB overview" dashboard](https://github.com/cybertec-postgresql/pgwatch2/raw/master/screenshots/overview.png)

# Technical details

* Dynamic management of monitored databases, metrics and their intervals - no need to restart/redeploy
* Safety
  - only one concurrent query per monitored database is allowed so side-effects shoud be minimal
  - configurable statement timeouts
  - SSL connections support for safe over-the-internet monitoring (use "-e PW2_WEBSSL=1 -e PW2_GRAFANASSL=1" when launching Docker)
  - Optional authentication for the Web UI and Grafana (by default freely accessible!)
* Backup script (take_backup.sh) provided for taking snapshots of the whole setup. To make it easier (run outside the container)
one should to expose ports 5432 (Postgres) and 8088 (InfluxDB backup protocol) at least for the loopback address.

Ports exposed by the Docker image:

* 5432 - Postgres configuration DB
* 8080 - Management Web UI (monitored hosts, metrics, metrics configurations)
* 3000 - Grafana dashboarding
* 8086 - InfluxDB API
* 8088 - InfluxDB Backup port

# The Web UI

For easy configuration changes (adding databases to monitoring, adding metrics) there is a small Python Web application bundled (exposed on Docker port 8080), making use of the CherryPy Web-framework. For mass changes one could technically also log into the configuration database and change the tables in the “pgwatch2” schema directly. Besides the configuration options the two other useful features would be the possibility to look at the logs of the single components and at the “Stat Statements Overview” page, which will e.g. enable finding out the query with the slowest average runtime for a time period.

# Adding metrics

Metric definitions – metrics are named SQL queries that can return pretty much everything you find 
useful and which can have different query text versions for different target PostgreSQL versions. 
Correct version of the metric definition will be chosen automatically by regularly connecting to the 
target database and checking the version. For defining metrics definitions you should adhere to a 
couple of basic concepts though:

* Every metric query should have an “epoch_ns” (nanoseconds since epoch, default InfluxDB timestamp 
precision) column to record the metrics reading time. If the column is not there, things will still 
work though as gathering server’s timestamp will be used, you’ll just lose some milliseconds 
(assuming intra-datacenter monitoring) of precision.
* Queries can only return text, integer, boolean or floating point (a.k.a. double precision) data.
* Columns can be optionally “tagged” by prefixing them with “tag_”. By doing this, the column data 
will be indexed by the InfluxDB giving following advantages:
  * Sophisticated auto-discovery support for indexed keys/values, when building charts with Grafana.
  * Faster InfluxDB queries for queries on those columns.
  * Less disk space used for repeating values. Thus when you’re for example returning some longish 
  and repetitive status strings (possible with Singlestat or Table panels) that you’ll be looking 
  up by some ID column, it might still make sense to prefix the column with “tag_” to reduce disks 
  space.

# Updating to a newer Docker version

pgwatch2 code part doesn't need too much maintenance itself (most issues seem to be related to dashboards that users 
can actually change themselves) but the main components that pgwatch2 relies on (Grafana, InfluxDB) 
are pretty active and get useful features and fixes quite regularly, thus we'll also try to push new 'latest' images, 
so it would make sense to check for updates time to time on [Docker Hub](https://hub.docker.com/r/cybertec/pgwatch2/tags/). 
NB! You could also choose to build your own image any time and the build scripts will download the latest components for you.

If possible (e.g. previously gathered metrics are not important and there are no user added dashboard/graphs) 
then the easiest way to get the latest Docker image would be just to stop the old one and doing 'docker pull/run' 
again as described in beginning of the README.  

If using a custom setup, switching out single components should be quite easy, just follow the component provider's  
instructions. Migrating data from the current Docker container to a newer version of the pgwatch2 Docker 
image on the other hand needs quite some steps currently. See the take_backup.sh script 
[here](https://github.com/cybertec-postgresql/pgwatch2/blob/master/take_backup.sh) for more details.

Basically there are two options – first, go into the Docker container (e.g. docker exec -it ps2 /bin/bash) 
and just update the component yourself – i.e. download the latest Grafana .deb package and install it with “dpkg -i …”. 
This is actually the simplest way. The other way would be to fetch the latest pgwatch2 image, which already has the 
latest version of components, using “docker pull” and then restore the data (InfluxDB + Postgres) from a backup of old 
setup. For restoring one needs to go inside the Docker container again but by following the steps described in 
take_backup.sh it shouldn't be a real problem.

A tip: to make the restore process easier it would already make sense to mount the host folder with the backups in it on the 
new container with “-v ~/pgwatch2_backups:/pgwatch2_backups:rw,z” when starting the Docker image. Otherwise one needs to set
up SSH or use something like S3 for example. Also note that ports 5432 and 8088 need to be exposed to take backups 
outside of Docker.
