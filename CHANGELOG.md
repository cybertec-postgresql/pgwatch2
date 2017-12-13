## Running the latest version

```docker run -d -p 3000:3000 -p 8080:8080 --name pw2 cybertec/pgwatch2```

or a specific version

```docker run -d -p 3000:3000 -p 8080:8080 --name pw2 cybertec/pgwatch2:x.y.z```

## v1.2.3 [2017-12-13]

* Fix for Web UI/Grafana HTTPS mode (outgoing links/logos are now also HTTPS)
* Fix for Docker image Go gatherer - config DB env parameters (PW2_PG*) are now fully respected
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
