# pgwatch2

Flexible self-contained PostgreSQL metrics monitoring/dashboarding solution

# Installing

Software is packaged as Docker (for custom setup see the last paragraph below, for a Docker quickstart see
[here](https://docs.docker.com/get-started/)) for getting started quickly.
```
# fetch and run the latest Docker image, exposing Grafana on port 3000 and administrative web UI on 8080
docker run -d -p 3000:3000 -p 8080:8080 --name pw2 cybertec/pgwatch2
```
After some minutes you could open the ["db-overview"](http://127.0.0.1:3000/dashboard/db/db-overview) dashboard and start
looking at metrics. For defining your own dashboards you need to log in as admin (admin/pgwatch2admin).
NB! If you don't want to add the "test" database (the pgwatch2 configuration db) for monitoring set the NOTESTDB=1 env
parameter when launching the image.

For production setups without a container management framework also "--restart unless-stopped"
(or custom startup scripts) is highly recommended. Also usage of volumes is then recommended to enable
easier updating to newer pgwatch2 Docker images without going through the backup/restore procedure described towards the
end of README. For maximum flexibility, security and update simplicity though, best would to do a custom setup - see
paragraph "Installing without Docker" towards the end of REAME for that. 

```
for v in pg influx grafana pw2 ; do docker volume create $v ; done
docker run -d --name pw2 -v pg:/var/lib/postgresql -v influx:/var/lib/influxdb -v grafana:/var/lib/grafana -v pw2:/pgwatch2/persistent-config -p 8080:8080 -p 3000:3000 cybertec/pgwatch2
```

For more advanced usecases (production setup backups) or for easier problemsolving you can decide to expose all services
```
# run with all ports exposed
docker run -d -p 3000:3000 -p 5432:5432 -p 8086:8086 -p 8080:8080 -p 8081:8081 -p 8088:8088 --name pw2 cybertec/pgwatch2
```
NB! For production usage make sure you also specify listening IPs explicitly (-p IP:host_port:container_port), by default Docker uses 0.0.0.0 (all network devices).

For custom options, more security, or specific component versions one could easily build the image themselves, just Docker needed:
```
docker build .
```

For a complete list of all supported Docker environment variables see [ENV_VARIABLES.md](https://github.com/cybertec-postgresql/pgwatch2/blob/master/ENV_VARIABLES.md)


# Features

* Easy extensibility by defining metrics in pure SQL (thus they could also be from business domain)
* Non-invasive setup, no extensions nor superuser rights required for the base functionality
* Global or DB level configuration of metrics/intervals
* Central config DB based operation or local config file based for better automation (Ansible, etc) or ad-hoc/test mode for
monitoring a single DB. See below for details
* Intuitive metrics presentation using the [Grafana](http://grafana.org/) dashboarding engine. Set of pre-defined dashboards provided
* Optional alerting (Email, Slack, PagerDuty) provided by Grafana
* PgBouncer and AWS RDS graphing/alerting supported in addition to PostgreSQL
* Possible to monitoring all DBs found in a cluster automatically (with regex pattern matching)
* Kubernetes/OpenShift ready
* Multiple metric storage options - InfluxDB, PostgreSQL, Graphite

# Project background

For more background on the project motivations and design goals see the original series of blogposts announcing the project:

* [Project announcement](https://www.cybertec-postgresql.com/en/announcing-pgwatch2-a-simple-but-versatile-postgresql-monitoring-tool/)
* [Implementation details](https://www.cybertec-postgresql.com/en/a-more-detailed-look-at-pgwatch2-postgresql-monitoring-tool/)
* [Feature pack 1](https://www.cybertec-postgresql.com/en/new-features-for-cybertecs-pgwatch2-postgres-monitoring-tool/)
* [Feature pack 2](https://www.cybertec-postgresql.com/en/updates-for-the-pgwatch2-postgres-monitoring-tool/)
* [Feature pack 3](https://www.cybertec-postgresql.com/en/pgwatch2-feature-pack-3/)

# Limitations / Performance expectations

* Min 1GB RAM
* Docker default disk size of 10 GB should be enough for monitoring 5 hosts (1 month default metrics retention policy, configurable)
* A low-spec (1 vCPU, 2 GB RAM) cloud machine can easily monitor 100 DBs in "exhaustive" settings (i.e. almost all metrics
are monitored with 60s interval) without breaking a sweat (<20% load). When a single node where the metrics collector daemon
is running is becoming a bottleneck, one can also do "sharding" i.e. limit the amount of monitored databases for that node
based on the Group label(s) (--group), which is just a string for logical grouping.
* One monitored DB in preset "exhaustive" settings requires about ~250-500 MB of InfluxDB disk storage per month, depending on
the amount of schema objects - tables, indexes, number of unique SQL-s.
* A single InfluxDB node should handle thousands of requests per second but if this is not enough having a secondary/mirrored
InfluxDB is also possible. If more than two needed (e.g. feeding many many Grafana instances or some custom exporting) one
should look at Influx Enterprise (on-prem or cloud) or Graphite (which is also supported as metrics storage backend).
* When high InfluxDB latency is problematic (e.g. using a DBaaS across the atlantic) then increasing the default maximum batching delay (--batching-delay-ms) of 250ms would give good results

# Security/safety aspects

Settings can be configured for most components, but by default the Docker image doesn't focus on security though but rather
on being quickly usable for ad-hoc performance troubleshooting. 

* No noticable impact for the monitored DB is expected with the default settings. For some metrics though can happen that the metric reading query (notably "stat_statements") takes some milliseconds, which might be more than an average application query. At any time only 2 metric fetching queries are running in parallel on the monitored DBs, with 5s per default "statement timeout" (configurable).
* Starting from v1.3.0 there's a non-root Docker version available (suitable for OpenShift)
* The administrative Web UI doesn't have by default any security. Configurable via env. variables.
* Viewing Grafana dashboards by default doesn't require login. Editing needs a password. Configurable via env. variables.
* InfluxDB has no authentication in Docker setup, so one should just not expose the ports when having concerns.
* Dashboards based on "pg_stat_statements" (Stat Statement Overview / Top) expose actual queries. They are mostly stripped
of details though, but if no risks can be taken the dashboards (or at least according panels) should be deleted. As an alternative "pg_stat_statements_calls"
can be used, which only records total runtimes and call counts.


# Alerting

Alerting is very conveniently (point-and-click style) provided by Grafana - see [here](http://docs.grafana.org/alerting/rules/)
for documentation. All most popular notification services are supported. A hint - currently you can set alerts only on Graph
panels and there must be no variables used in the query so you cannot use the pre-created pgwatch2 graphs.

If more complex scenarios/check conditions are required TICK stack and Kapacitor can be easily integrated - see 
[here](https://www.influxdata.com/time-series-platform/#kapacitor) for more details. 

# Components

* pgwatch2 metrics gathering daemon written in Go
* A PostgreSQL database for holding the configuration about which databases and metrics to gather 
* [InfluxDB](https://www.influxdata.com/time-series-platform/influxdb/) Time Series Database for storing metrics. As an
alternative to InfluxDB one can also use:
  - Graphite (no custom_tags support)
  - PostgreSQL (based on JSONB, 9,4+)
* [Grafana](http://grafana.org/) for dashboarding (point-and-click, a set of predefined dashboards is provided)
* A Web UI for administering the monitored DBs and metrics and for showing some custom metric overviews

NB! All component can be also used separately, thus you can decide to make use of an already existing installation of Postgres,
Grafana or InfluxDB and run the pgwatch2 image for example only with the metrics gatherer and the configuration Web UI.
These external installations must be accessible from within the Docker though. For info on installation without Docker
at all see end of README.

## Component diagram for default Docker setup

![Component diagram](https://raw.githubusercontent.com/cybertec-postgresql/pgwatch2/master/screenshots/pgwatch2_architecture.png)

### To use an existing Postgres DB for storing the monitoring config

Create a new pgwatch2 DB, preferrably also an accroding role who owns it. Then roll out the schema (pgwatch2/sql/config_store/config_store.sql)
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

### To use an existing Postgres DB for storing metrics

1. Create the [schema](https://github.com/cybertec-postgresql/pgwatch2/blob/master/pgwatch2/sql/metric_store/metric_store.sql)
2. Following parameters needs to be set for the gatherer:
  - --datastore=postgres or PW2_DATASTORE=postgres
  - --pg-metric-store-conn-str="postgresql://user:pwd@host:port/db" or PW2_PG_METRIC_STORE_CONN_STR="..."

NB! Currently for Postgres though there is only predefined pgwatch2 dashboard (DB Overview), so you need to roll your own.


# Usage (Docker based, for file or ad-hoc based see further below)

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

* As a base requirement you'll need a login user (non-superuser suggested) for connecting to your server and fetching metrics queries.
NB! Though theoretically you can use any username you like, but if not using "pgwatch2" you need to modify the "helper" creation
scripts accordingly as in those by default only the "pgwatch2" will be granted execute privileges.
```
create role pgwatch2 with login password 'secret';
```
* Define the helper function to enable the monitoring of sessions, blocking locks, etc by the `pgwatch2` login defined above, if using a superuser login (not recommended) you can skip this step, just ensure that you check the `Is superuser?` check box when configuring Databases
```
psql -h mydb.com -U superuser -f pgwatch2/sql/metric_fetching_helpers/stat_activity_wrapper.sql mydb
```

* Additionally for extra insights ("Stat statements" dashboard and CPU load) it's also recommended to install the pg_stat_statement
extension (Postgres 9.4+ needed to be useful for pgwatch2) and the PL/Python language. The latter one though is usually disabled by DB-as-a-service providers for security reasons.
For maximum pg_stat_statement benefit ("Top queries by IO time" dashboard), one should also then enable the [track_io_timing](https://www.postgresql.org/docs/current/static/runtime-config-statistics.html#GUC-TRACK-IO-TIMING) setting.

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

# Running without helper / wrapper functions

Helpers/wrappers are not needed actually, they just provide a bit more information. For unprivileged users (developers)
with no means to install any wrappers as superuser it's also possible to benefit from pgwatch2 - for such use cases e.g.
the "unprivileged" preset metrics profile and the according ["DB overview Unprivileged / Developer" dashboard](https://raw.githubusercontent.com/cybertec-postgresql/pgwatch2/master/screenshots/overview_developer.png)
is a good starting point as it only assumes existance of pg_stat_statements.

# Screenshot of the "DB overview" dashboard
!["DB overview" dashboard](https://github.com/cybertec-postgresql/pgwatch2/raw/master/screenshots/overview.png)

More screenshots [here](https://github.com/cybertec-postgresql/pgwatch2/tree/master/screenshots)

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
* 8081 - Gatherer healthcheck / statistics on number of gathered metrics (JSON).
* 3000 - Grafana dashboarding
* 8086 - InfluxDB API
* 8088 - InfluxDB Backup port

# The Admin Web UI

In the centrally managed (config DB based) mode, for easy configuration changes (adding databases to monitoring, adding
metrics) there is a small Python Web application bundled (exposed on Docker port 8080), making use of the CherryPy
Web-framework. For mass changes one could technically also log into the configuration database and change the tables in
the “pgwatch2” schema directly. Besides managing the metrics gathering configurations, the two other useful features for
the Web UI would be the possibility to look at the logs of the single components (when using Docker) and at the “Stat
Statements Overview” page, which will e.g. enable finding out the query with the slowest average runtime for a time period.

By default the Web UI is freely accessible. If some security is needed then following env. variables can be used enforce
write permissions - PW2_WEBNOANONYMOUS, PW2_WEBUSER, PW2_WEBPASSWORD.

By default also the Docker component logs (Postgres, Influx, Grafana, Go daemon, Web UI itself) are exposed via the "/logs"
endpoint. If this is not wanted set the PW2_WEBNOCOMPONENTLOGS env. variable.  

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
* Fixed per host "custom tags" are also supported - these can contain any key-value data important to user and are
added to all captured data rows

# File based operation

From v1.4.0 one can also deploy pgwatch2 gatherer daemons decentrally, based on YAML config files - for both metric definitions
and "hosts to be monitored" definitions. In that case there is no need for the central Postgres "config DB". See
"pgwatch2/config/instances.yaml" for sample config file and "pgwatch2/metrics" folder for metrics (and preset metric
configuration) definitions. Relevant Gatherer env. vars / flags: PW2_CONFIG / --config, PW2_METRICS_FOLDER / --metrics-folder.

# Ad-hoc operation

From v1.4.0 it's also possible to run the gatherer daemon in ad-hoc / test mode, by giving a single standard connection
string as input, and optionally also specifying the metrics to monitor (preset config name or a custom JSON string).
In that case there is no need for the central Postgres "config DB" nor the YAML file specifying which hosts to monitor.
NB! When using that mode with the default Docker image, the built-in metric definitions can't be changed via the Web UI.
Relevant Gatherer env. vars / flags: --adhoc-conn-str, --adhoc-config, --adhoc-name, --metrics-folder / PW2_ADHOC_CONN_STR, PW2_ADHOC_CONFIG, PW2_ADHOC_NAME, PW2_METRICS_FOLDER.

```
# launching in ad-hoc / test mode
docker run --rm -p 3000:3000 -p 8080:8080 -e PW2_ADHOC_CONN_STR="postgresql://user:pwd@mydb:5432/mydb1" -e PW2_ADHOC_CONFIG=unprivileged --name pw2 cybertec/pgwatch2
```
NB! In ad-hoc mode pgwatch2 always tries (will succeed if connecting with superuser privileges) to create all of the
metrics fetching helpers automatically on the monitored DB.

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
[here](https://github.com/cybertec-postgresql/pgwatch2/blob/master/take_backup.sh) for more details. To make updates a
bit easier, the preferred way should be though to think about it previously and use Docker volumes accordingly - see the
Dockerfile for details. On some rare occasions updating to newer pgwatch2 Web UI or gahterer daemon might additionally
still require rollout of some manual config DB schema migrations scripts from the "migrations" subfolder - error messages
will include "missing columns" or "wrong datatype" then. SQL "patches" might be provided also for important metric updates,
but for dashboard changes there will be none - users need to import them from JSON directly!

Basically there are two options – first, go into the Docker container (e.g. docker exec -it pw2 /bin/bash)
and just update the component yourself – i.e. download the latest Grafana .deb package and install it with “dpkg -i …”. 
This is actually the simplest way. The other way would be to fetch the latest pgwatch2 image, which already has the 
latest version of components, using “docker pull” and then restore the data (InfluxDB + Postgres) from a backup of old 
setup. For restoring one needs to go inside the Docker container again but by following the steps described in 
take_backup.sh it shouldn't be a real problem.

A tip: to make the restore process easier it would already make sense to mount the host folder with the backups in it on the 
new container with “-v ~/pgwatch2_backups:/pgwatch2_backups:rw,z” when starting the Docker image. Otherwise one needs to set
up SSH or use something like S3 for example. Also note that ports 5432 and 8088 need to be exposed to take backups 
outside of Docker.

# Installing without Docker

All examples assuming Ubuntu.

1. Install Postgres and create DB-s/roles for pgwatch2/Grafana
    
    ```
    sudo apt install postgresql
    ```
    Default port: 5432
    
    1.1. Create an User and a DB to hold Grafana config
    ```
    psql -c "create user pgwatch2_grafana password 'xyz'"
    psql -c "create database pgwatch2_grafana owner pgwatch2_grafana"
    ```
    
    1.2. Create an User and a DB to hold pgwatch2 config
    
    ```
    psql -c "create user pgwatch2 password 'xyz'"
    psql -c "create database pgwatch2 owner pgwatch2"
    ```
    
    1.3 Roll out the pgwatch2 schema (will holds connection strings of DB-s to be monitored + metric definitions)
    
    ```
    psql -f pgwatch2/sql/config_store/config_store.sql pgwatch2
    psql -f pgwatch2/sql/config_store/metric_definitions.sql pgwatch2
    ```
2. Install InfluxDB
    
    ```
    INFLUX_LATEST=$(curl -so- https://api.github.com/repos/influxdata/influxdb/tags | grep -Eo '"v[0-9\.]+"' | grep -Eo '[0-9\.]+' | sort -nr | head -1)
    wget https://dl.influxdata.com/influxdb/releases/influxdb_${INFLUX_LATEST}_amd64.deb
    sudo dpkg -i influxdb_${INFLUX_LATEST}_amd64.deb
    ```
    Take a look/edit the Influx config at /etc/influxdb/influxdb.conf and it's recommend to create also a separate limited
    login user e.g. "pgwatch2" to be used by the metrics gathering daemon to store metrics. See [here](https://docs.influxdata.com/influxdb/latest/administration/config/)
    on configuring InfluxDB and [here](https://docs.influxdata.com/influxdb/latest/query_language/authentication_and_authorization/#user-types-and-privileges)
    for creating new users.
    
    Default port for the API: 8086

3. Install Grafana
    
    ```
    GRAFANA_LATEST=$(curl -so- https://api.github.com/repos/grafana/grafana/tags | grep -Eo '"v[0-9\.]+"' | grep -Eo '[0-9\.]+' | sort -nr | head -1)
    wget https://s3-us-west-2.amazonaws.com/grafana-releases/release/grafana_${GRAFANA_LATEST}_amd64.deb
    sudo dpkg -i grafana_${GRAFANA_LATEST}_amd64.deb
    ```
    Default port: 3000
    
    2.1. Configure Grafana config to use our pgwatch2_grafana DB
    
    Place something like below in the "[database]" section of /etc/grafana/grafana.ini
    
    ```
    [database]
    type = postgres
    host = my-postgres-db:5432
    name = pgwatch2_grafana
    user = pgwatch2_grafana
    password = xyz
    ```
    
    Taking a look at [server], [security] and [auth*] sections is also recommended.
    
    2.2. Set up the Influx datasource as default
    
    Use the Grafana UI (Admin -> Data sources) or adjust and execute the "pgwatch2/bootstrap/grafana_datasource.sql"
    
    2.3. Add pgwatch2 predefined dashboards to Grafana
    
    This could be done by importing the JSON-s from the "grafana_dashboards" folder manually (Import Dashboard from the Grafana
    top menu) or via the Docker bootstrap script (pgwatch2/bootstrap/set_up_grafana_dashboards.sh). Script needs some adjustment
    for connect data and file paths though and also the "grafana_datasource.sql" part should be commented out if already
    executed in the previous step.
    
4. Install Python 3 and start the Web UI
    
    NB! The Web UI is not strictly required but makes life a lot easier. Technically it would be fine also to manage connection
    strings of the monitored DB-s directly in the "pgwatch2.monitored_db" table and add/adjust metrics in the "pgwatch2.metric" table,
    and "preset configs" in the "pgwatch2.preset_config" table.
    
    ```
    # first we need Python 3 and "pip" - the Python package manager
    sudo apt install python3 python3-pip
    sudo pip3 install -U -r webpy/requirements.txt 
    ```
    
    4.0. Optional step: for use cases where exposing component (Grafana, Postgres, Influx, gatherer daemon, Web UI itself) logs via the
    Web UI could be benficial, one should also change the log file paths hardcoded in the SERVICES variable of the pgwatch2.py source
    file. Defaults are set to work with the Docker image.

    4.1. Start the Web UI
    ```
    cd webpy
    python3 web.py
    ```
    Default port for the Web UI: 8080
    
    4.2. Configure DB-s to monitor from "/dbs" page
    
    NB! To get most out of your metrics some wrappers/extensions are required on the DB-s under monitoring.
    See section [Steps to configure your database for monitoring](https://github.com/cybertec-postgresql/pgwatch2#steps-to-configure-your-database-for-monitoring) on
    setup information.
    
5. Install Go and compile the gatherer
    
    Check for the latest Go version from https://golang.org/dl/
    
    ```
    # install Go (latest version preferably, but at least 1.10)
    wget https://dl.google.com/go/go1.11.linux-amd64.tar.gz
    tar -C /usr/local -xzf go1.11.linux-amd64.tar.gz
    export PATH=$PATH:/usr/local/go/bin
    
    # compile the gatherer daemon
    cd pgwatch2
    ./build_gatherer.sh
    # an executable named "pgwatch2" should be generated ...
    ```
    
      5.1. Run the gatherer
    
    ```
    ./pgwatch2 --host=my-postgres-db --user=pgwatch2 --password=xyz  \
        --ihost=my-influx-db --iuser=pgwatch2 --ipassword=xyz
    
    # for all starting options run "./pgwatch2 --help"
    ```

    Congrats! Now the metrics should start flowing in and after some minutes one should already see some graphs in Grafana.

6. Make sure to hatch up some "init scripts" so that the pgwatch2 daemon and the Web UI would be started automatically
when the system reboots. For externally packaged components (Grafana, Influx, Postgres) it should be the case already.
