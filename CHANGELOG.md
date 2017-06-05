## Running the latest version

```docker run -d -p 3000:3000 -p 8080:8080 --name pw2 cybertec/pgwatch2```

or a specific version

```docker run -d -p 3000:3000 -p 8080:8080 --name pw2 cybertec/pgwatch2:x.y.z```


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
