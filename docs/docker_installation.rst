Installing using Docker
=======================

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
* some predefine metrics (cpu_load, stat_statements) require installing helper functions (look into "pgwatch2/metrics/00_helpers" folder) on monitored DBs2
* for effective graphing you want to familiarize yourself with basic InfluxQL and the non_negative_derivative() function
which is very handy as Postgres statistics are mostly evergrowing counters. Documentation [here](https://docs.influxdata.com/influxdb/latest/query_language/functions/#non-negative-derivative).
* for troubleshooting, logs for the components are visible under http://127.0.0.1:8080/logs/[pgwatch2|postgres|webui|influxdb|grafana] or by logging
into the docker container under /var/logs/supervisor/




Docker Compose
==============

ASasa