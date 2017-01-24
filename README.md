# pgwatch2
PostgreSQL metrics monitor/dashboard

# Installing

Software is packaged as Docker so getting started should be easy
```
# fetch the latest Docker image
docker pull cybertec/pgwatch2 
# run the image, exposing Grafana on port 3000 and administrative web UI on 8080
docker run -d -p 3000:3000 8080:8080 --name pw2 cybertec/pgwatch2
```
After a minute you could open a browser at 0.0.0.0:3000 and start looking at metrics and defining your own dashboards. 
With some configuration also alerting is possible via Grafana.  


For more advanced usecases or for easier problemsolving you can decide to expose all services
```
# run with all ports exposed
docker run -d -p 3000:3000 -p 5432:5432 -p 8083:8083 -p 8086:8086 -p 8080:8080 -p 8088:8088 --name pw2 cybertec/pgwatch2
```

For building the image yourself one needs currently also Go as the metrics gathering daemon is written in it.
```
./builds.sh
docker run -d -p 3000:3000 -p 8080:8080 --name pw2 $HASH_FROM_PREV_STEP
```


# Components

* pgwatch2 metrics gathering daemon written in Go
* A PostgreSQL database for holding the configuration about which databases and metrics to gather 
* InfluxDB Time Series Database for storing metrics (exposing 3 ports)
* Grafana for dashboarding (a set of predefined dashboards is provided)
* A Web UI for administering the monitored DBs and showing custom metric overviews

# Usage 

* by default the "pgwatch2" configuration database running inside Docker is being monitored so that you can immediately see
  some graphs, but you should add new databases by opening the "admin interface" at 0.0.0.0:8080/dbs or logging into the
  Postgres config DB and inserting into "pgwatch2.monitored_db" table (db - pgwatch2 , default user/pw - postgres/pgwatch2admin)
* one can create new Grafana dashboards (and change settings, create users, alerts, ...) after logging in as "admin" (admin/pgwatch2admin)
* metrics (and their intervals) that are to be gathered can be customized for every database by using a preset config
like "minimal", "basic" or "exhaustive" (monitored_db.preset_config table) or a custom JSON config.
* to add a new metrics  yourself (simple SQL queries returing point-in-time values) head to http://0.0.0.0:8080/metrics.
The queries should always include a "epoch_ns" column and "tag_" prefix can be used for columns that should be tags
(thus indexed) in InfluxDB.
* a list of available metrics together with some instructions is also visible from the "Documentation" dashboard
* for effective graphing you want to familiarize yourself with basic InfluxQL and the non_negative_derivative() function
which is very handy as Postgres statistics are mostly evergrowing counters. Documentation [here](https://docs.influxdata.com/influxdb/v1.2/query_language/functions/#non-negative-derivative).
* logs for components are visible under http://0.0.0.0:8080/logs/[pgwatch2|postgres|webui|influxdb|grafana] or by logging
into the docker container under /var/logs/supervisor/.
