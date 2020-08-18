# Technical details

* Dynamic management of monitored databases, metrics and their intervals - no need to restart/redeploy
* Safety
  - Up to 2 concurrent queries per monitored database (thus more per cluster) are allowed
  - Configurable statement timeouts per DB
  - SSL connections support for safe over-the-internet monitoring (use "-e PW2_WEBSSL=1 -e PW2_GRAFANASSL=1" when launching Docker)
  - Optional authentication for the Web UI and Grafana (by default freely accessible)
* Backup script (take_backup.sh) provided for taking snapshots of the whole Docker setup. To make it easier (run outside the container)
one should to expose ports 5432 (Postgres) and 8088 (InfluxDB backup protocol) at least for the loopback address.

Ports exposed by the Docker image:

* 5432 - Postgres configuration (or metrics storage) DB
* 8080 - Management Web UI (monitored hosts, metrics, metrics configurations)
* 8081 - Gatherer healthcheck / statistics on number of gathered metrics (JSON).
* 3000 - Grafana dashboarding
* 8086 - InfluxDB API (when using the InfluxDB version)
* 8088 - InfluxDB Backup port (when using the InfluxDB version)