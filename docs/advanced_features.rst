Advanced features
=================

Over the years the core functionality of fetching metrics from a set of plain Postgres DB-s has been extended in many ways
to cover some common problems like log parsing and supporting monitoring of some other popular tools ofter used together
with Postgres, like the PgBouncer connection pooler for example.

Patroni support
---------------

Patroni is a popular Postgres specific HA-cluster manager that makes node management simpler than ever, meaning that everything
is dynamic though - cluster members can come and go, making monitoring in the standard way a bit tricky. But luckily Patroni
cluster members information is stored in a DCS (Distributed Consensus Store), like *etcd*, so it can be fetched from there
continuously.

When 'patroni' is selected as *DB type* then the usual host/port fields should be left empty ("dbname" can still filled if
only a specific single database is to be monitored) and instead "Host config" JSON field should be filled with DCS address,
type and scope (cluster name) information. A sample config (for Config DB based setups) looks like:

::

    {
      "dcs_type": "etcd",
      "dcs_endpoints": ["http://127.0.0.1:2379"],
      "scope": "batman",
      "namespace": "/service/"
    }

For YAML based setups an example can be found from the `instances.yaml <https://github.com/cybertec-postgresql/pgwatch2/blob/master/pgwatch2/config/instances.yaml#L34>`_ file.

NB! For *etcd* also username, password, ca_file, cert_file, key_file optional parameters can be defined - other DCS systems
are currently supported only without authentication.

Also if you don't use the replicas actively for queries then it might make sense to decrease the volume of gathered
metrics and to disable the monitoring of standby nodes with the "Master mode only?" checkbox (when using the Web UI) or
with *only_if_master=true* if using a YAML based setup.

Log parsing
-----------

As of v1.7.0 the metrics collector daemon, when running on a DB server (controlled best over a YAML config), has capabilities
to parse the database server logs. Out-of-the-box it will though only work when logs are written in **CVSLOG** format. For other
formats user needs to specify a regex that parses out named groups of following fields: *database_name*, *error_severity*.
See `here <https://github.com/cybertec-postgresql/pgwatch2/blob/master/pgwatch2/logparse.go#L27>`_ for an example regex.

NB! Note that only the event counts are stored, by severity, for the monitored DB and for the whole instance - no error
texts or username infos! The metric name to enable log parsing is "server_log_event_counts". Also note that for auto-detection
of log destination / setting to work the monitoring user needs superuser / pg_monitor rights - if this is not possible
then log settings need to be specified manually under "Host config" as seen for example `here <https://github.com/cybertec-postgresql/pgwatch2/blob/master/pgwatch2/config/instances.yaml>`_.

**Sample configuration if not using CSVLOG logging:**

On Postgres side (on the monitored DB)

::

    # Debian / Ubuntu default log_line_prefix actually
    log_line_prefix = '%m [%p] %q%u@%d '

YAML config (typically only used with YAML in "push" mode)

::

    ## logs_glob_path is only needed if the monitoring user is cannot auto-detect it (i.e. not a superuser / pg_monitor role)
    # logs_glob_path:
    logs_match_regex: '^(?P<log_time>.*) \[(?P<process_id>\d+)\] (?P<user_name>.*)@(?P<database_name>.*?) (?P<error_severity>.*?): '

NB! Additionally the metric **server_log_event_counts** needs to be enabled also, or a *preset* including it - like the
"full" preset.

PgBouncer support
-----------------

Pgwatch2 also supports collecting internal statistics from the PgBouncer connection pooler, via the built-in special
"pgbouncer" database and ``SHOW STATS`` command. To enable it choose the according *DB Type*, provide connection
info to the pooler port and make sure the **pgbouncer** metric / preset config is selected for the host.

There's also a built-in Grafana dashboard for PgBouncer data, looking like that:

.. image:: https://raw.githubusercontent.com/cybertec-postgresql/pgwatch2/master/screenshots/pgbouncer_stats.png
   :alt: Grafana dash for PgBouncer stats
   :target: https://raw.githubusercontent.com/cybertec-postgresql/pgwatch2/master/screenshots/pgbouncer_stats.png



Pgpool-II support
-----------------

asasas

AWS / Azure support
-------------------

asdas