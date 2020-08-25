List of main features
=====================

* Non-invasive setup on PostgreSQL side - no extensions nor superuser rights are required for the base functionality so that
  even unprivileged users like developers can get a good overview of database activities without any hassle

* Lots preset metric configurations covering all performance critical PostgreSQL internal Statistics Collector data

* Intuitive metrics presentation using a set of predefine dashboards for the very popular Grafana dashboarding engine with optional alerting

* Easy extensibility of metrics which are defined in pure SQL, thus they could also be from the business domain

* Many metric data storage options - PostgreSQL, PostgreSQL with TimescaleDB extension, InfluxDB, Graphite or Prometheus scraping

* Multiple deployment options - YAML, PostgreSQL or ENV configuration supporting both "push" and "pull" models

* Possible to monitoring all, single or a subset (list or regex) of databases of a PostgreSQL cluster

* Global or per DB configuration of metrics and metric fetching intervals and optionally also times / days

* Kubernetes/OpenShift ready with sample templates and a Helm chart

* PgBouncer, Pgpool2, AWS RDS and Patroni support with automatic cluster discovery

* Internal health-check API (port 8081 by default) to monitor metrics gathering status / progress remotely

* Built-in security with SSL connections and passwords encryption support for all components

* Very low resource requirements for the collector even when monitoring hundreds of instances

* Capabilities to go beyond PostgreSQL metrics gathering with built-in log parsing for error detection and OS level metrics
  collection via PL/Python "helper" stored procedures.

* A *Ping mode* to test connectivity to all databases under monitoring
