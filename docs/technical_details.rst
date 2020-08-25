Technical details of the metrics collector
==========================================

Here some technical details that might be interesting for those who are planning to use pgwatch2 for critical monitoring tasks.

* Dynamic management of monitored databases, metrics and their intervals - no need to restart/redeploy

* Safety features

  * Up to 2 concurrent queries per monitored database (thus more per cluster) are allowed

  * Configurable statement timeouts per DB

  * SSL connections support for safe over-the-internet monitoring (use "-e PW2_WEBSSL=1 -e PW2_GRAFANASSL=1" when launching Docker)

  * Optional authentication for the Web UI and Grafana (by default freely accessible)

* Backup script (take_backup.sh) provided for taking snapshots of the whole Docker setup. To make it easier (run outside the container)
  one should to expose ports 5432 (Postgres) and 8088 (InfluxDB backup protocol) at least for the loopback address.
