## Running the latest version

```docker run -d -p 3000:3000 -p 8080:8080 --name pw2 cybertec/pgwatch2```

or a specific version

```docker run -d -p 3000:3000 -p 8080:8080 --name pw2 cybertec/pgwatch2:x.y.z```


## v1.2.0

* Deletion of InfluxDB data from the Web UI now possible
* Adding of all databases from a host now possible when leaving "DB name" empty
* All components (Grafana, Postgres, InfluxDB/Graphite) made externally pluggable i.e. you can use your
existing setups. See README for details
* Fixed login page (no new window)
* Not exposing port 8083 anymore as InfluxDB UI was deprecated
* Better validations and tooltips for the monitored hosts ("/dbs") page in Web UI
* An env. flag not to create the "test" database when launching a pgwatch2 container (-e NOTESTDB=1)
* InfluxDB 1.3.5 - lots of bugfixes and perf improvements
* Grafana 4.5.1 - query inspection, better query builders and data tables

## v1.1.0

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

## v1.0.5

* Couple of smaller "Overview" dashboard corrections
* InfluxDB update from 1.2.0 to 1.2.2
* Grafana update from 4.1.2 to 4.2.0
