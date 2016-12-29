# pgwatch2
PostgreSQL metrics monitor/dashboard

# Installing

Software is packaged as Docker so getting started should be easy
```
docker pull cybertec/pgwatch2 
docker run -d -p 3000:3000 -p 5433:5432 -p 8083:8083 -p 8086:8086 -p 8080:8080 --name pw2 cybertec/pgwatch2
```
After a minute you could open a browser at 0.0.0.0:3000 and start looking at metrics and defining your own dashboards. 
With some configuration also alerting is possible via Grafana.  

For building it yourself one needs currently also Go.
```
./builds.sh
docker run -d -p 3000:3000 -p 5433:5432 -p 8083:8083 -p 8086:8086 -p 8080:8080 --name pw2 $HASH_FROM_PREV_STEP
```


# Components

* pgwatch2 metrics gathering daemon written in Go
* A PostgreSQL database for holding the configuration about which databases and metrics to gather 
* InfluxDB Time Series Database for storing metrics
* Grafana for dashboarding (a set of predefined dashboards is provided)
* A Web UI for administering the monitored DBs and showing custom metric overviews

# Usage 

* one can create new dashboards freely after logging in as "admin" (admin/pgwatch2admin)
* by default the "pgwatch2" configuration database running inside Docker is being monitored but you can add new ones by 
logging into the Postgres config DB and inserting into "pgwatch2.monitored_db" table (db - pgwatch2 , user/pw - postgres/pgwatch2admin) 
or via the UI at 0.0.0.0:8080/dbs
* to add new metrics head to http://0.0.0.0:8081/metrics. The queries should always include a "epoch_ns" column and "tag_" 
prefix can be used for columns that should be indexed in InfluxDB.
* metrics that are gathered (or intervals) can be customized for every database by using a preset configf 
("monitored_db.md_preset_config_name" is a FK to "preset_config.pc_name") or a custom JSON config (monitored_db.md_config)
* a list of available metrics together with some instructions are visible in the "Documentation" dashboard
* for effective graphing you need to familiarize yourself with basic InfluxQL and the non_negative_derivative() function. 
Documentation [here](https://docs.influxdata.com/influxdb/v1.1//query_language/functions/#non-negative-derivative).
* logs for components are visible under http://0.0.0.0:8081/logs/[pgwatch2|postgres|webui|influxdb|grafana] or by logging 
into the docker container
