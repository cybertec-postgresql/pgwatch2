.. _preparing_databases:

Preparing databases for monitoring
==================================

Effects of monitoring
---------------------

* Although the "Observer effect" applies also for pgwatch2, no noticeable impact for the monitored DB is expected with the
  default settings, given that there is some normal load on the server anyways.  For some metrics though can happen that
  the metric reading query (notably "stat_statements" and "table_stats") takes some tens of milliseconds, which might be
  more than an average application query.

* At any time maximally 2 metric fetching queries can run in parallel on any monitored DBs. This can be changed be recompiling
  (MAX_PG_CONNECTIONS_PER_MONITORED_DB variable).

* Default Postgres `statement timeout <https://www.postgresql.org/docs/current/runtime-config-client.html#GUC-STATEMENT-TIMEOUT>`_
  is *5s* for entries inserted via the Web UI.

Basic preparations
------------------

As a base requirement you'll need a **login user** (non-superuser suggested) for connecting to your server and fetching metrics queries.

Though theoretically you can use any username you like, but if not using "pgwatch2" you need to adjust the "helper" creation
SQL scripts (see below for explanation) accordingly as in those by default only the "pgwatch2" will be granted execute privileges.

::

  CREATE ROLE pgwatch2 WITH LOGIN PASSWORD 'secret';
  -- NB! For critical databases it might make sense to ensure that the user account
  -- used for monitoring can only open a limited number of connections
  -- (there are according checks in code, but multiple instances might be launched)
  ALTER ROLE pgwatch2 CONNECTION LIMIT 3;
  GRANT pg_monitor TO pgwatch2;   // v10+

For most monitored databases it's extremely beneficial (for troubleshooting performance issues) to also activate the
**pg\_stat\_statements** extension which will give us exact "per query" performance aggregates and also enables to calculate
how many queries are executed per second for example. In pgwatch2 context it powers the "Stat statements Top" dashboard
and many other panels of other dashboards. For additional benefit also the `track_io_timing <https://www.postgresql.org/docs/current/static/runtime-config-statistics.html#GUC-TRACK-IO-TIMING>`_
setting should be enabled.

#. Make sure the Postgres *contrib* package is installed.

   * On RedHat / Centos: ``yum install -y postgresqlXY-contrib``

   * On Debian / Ubuntu: ``apt install postgresql-contrib``

#. Add *pg_stat_statements* to your server config (postgresql.conf) and restart the server.

   ::

     shared_preload_libraries = 'pg_stat_statements'
     track_io_timing = on

#. After restarting activate the extension in the monitored DB. Assumes Postgres superuser.

   ::

     psql -c "CREATE EXTENSION IF NOT EXISTS pg_stat_statements"

.. _helper_functions:

Rolling out helper functions
----------------------------

Helper functions in pgwatch2 context are standard Postgres stored procedures, running under *SECURITY DEFINER* privileges.
Via such wrappers functions one can do **controlled privilege escalation** - i.e. to give access to protected Postgres
(active session details, "per query" statistics) or OS-level metric data also to normal unprivileged users, like the pgwatch2
monitoring role.

If using a superuser login (not recommended for remote "pulling", but only local "pushing" users) you have full access to
all Postgres metrics and would need *helpers* only for OS statistics (as of v1.6.0).

For unprivileged monitoring users it is highly recommended to take these additional steps on the "to be monitored"
database to get maximum value out of pgwatch2 in the long run. Without these additional steps, you lose though about
10-15% of built-in metrics, which might not be too tragical nevertheless and for that use case there's also a *preset config*
named "unprivileged".

NB! When monitoring v10+ servers then the built-in **pg_monitor** system role is recommended for the monitoring user, which
almost substitutes superuser privileges for monitoring purposes.

**Rolling out common helpers**

For completely unprivileged monitoring users the following *helpers* are recommended to make good use of the default
"exhaustive" *preset config*:

::

  export PGUSER=superuser
  psql -f /etc/pgwatch2/metrics/00_helpers/get_stat_activity/$pgver/metric.sql mydb
  psql -f /etc/pgwatch2/metrics/00_helpers/get_stat_replication/$pgver/metric.sql mydb
  psql -f /etc/pgwatch2/metrics/00_helpers/get_wal_size/$pgver/metric.sql mydb
  psql -f /etc/pgwatch2/metrics/00_helpers/get_stat_replication/$pgver/metric.sql mydb

NB! Note that there might not be an exact Postgres version match for helper definitions - then replace $pgver with the next
available version number above your server's Postgres version number.

Also when rolling out helpers make sure the `search_path` is set correctly (same as monitoring role's) as metrics using the
helpers, assume that monitoring role's `search_path` includes everything needed i.e. they don't qualify any schemas.

For more detailed statistics (OS monitoring, table bloat, WAL size, etc) it is recommended to install also all other helpers
found from the `/etc/pgwatch2/metrics/00_helpers` folder or do it automatically by using the *rollout_helper.py* script
found in the *00_helpers* folder.

As of v1.6.0 though helpers are not needed for Postgres-native metrics (e.g. WAL size) if a privileged user (superuser
or *pg_monitor* GRANT) is used, as pgwatch2 now supports having 2 SQL definitions for each metric - "normal / unprivileged"
and "privileged" / "superuser". In the file system such "privileged" access definitions will have a "\_su" added to the file name.

Automatic rollout of helpers
----------------------------

pgwatch2 can roll out *helpers* also automatically on the monitored DB. This requires superuser privileges and a configuration
attribute for the monitored DB. In YAML config mode it's called *is_superuser*, in Config DB *md_is_superuser* or ticking
the "Auto-create helpers" checkbox in the Web UI or *--adhoc-create-helpers* / *PW2_ADHOC_CREATE_HELPERS* in *ad-hoc* mode.

After the automatic rollout though it's still recommended to switch real monitoring back to the unprivileged *pgwatch2* role,
which now has GRANT-s to all created functions. Note though that all created helpers will not be immediately usable as
some are for special purposes and need additional dependencies.

A hint: if it can be foreseen that a lot of databases will be created on some instance (generally not a good idea though) it
might be a good idea to roll out the helpers directly in the *template1* database - so that all newly created databases
will get them automatically.

PL/Python helpers
-----------------

PostgreSQL in general is implemented in such a way that it does not know too much about the operation system that it is
running on. This is a good thing for portability but can be somewhat limiting for monitoring, especially when there is no
*system monitoring* framework in place or the data just not conveniently accessible together with metrics gathered from Postgres.
To overcome this problem, users can also choose to install *helpers* extracting OS metrics like CPU, RAM, etc usage and
storing them together with Postgres-native metrics for easier graphing / alerting. This also enable to be totally independent
of any System Monitoring tools like Zabbix, etc.

Note though that PL/Python is usually disabled by DB-as-a-service providers like AWS RDS for security reasons.

::

    # first install the Python bindings for Postgres
    apt install postgresql-plpython3-XY
    # yum install postgresqlXY-plpython3

    psql -c "CREATE EXTENSION plpython3u"
    psql -f /etc/pgwatch2/metrics/00_helpers/get_load_average/9.1/metrics.sql mydb

Note that we're assuming here that we're on a modern Linux system with Python 3 as default. For older systems Python 3
might not be an option though, so you need to change *plpython3u* to *plpythonu* and also do the same replace inside the
code of the actual helper functions! Here the *rollout_helper.py* script with the ``--python2`` flag can be helpful again.

Notice on using metric fetching helpers
---------------------------------------

* When installing some "helpers" and laters doing a binary PostgreSQL upgrade via `pg_upgrade`, this could result in some
  error messages thrown. Then just drop those failing helpers on the "to be upgraded" cluster and re-create them after the upgrade process.

* Starting from Postgres v10 helpers are mostly not needed (only for PL/Python ones getting OS statistics) - there are available
  some special monitoring roles like "pg_monitor", that are exactly meant to be used for such cases where we want to give access
  to all Statistics Collector views without any other "superuser behaviour". See `here <https://www.postgresql.org/docs/current/default-roles.html>`_
  for documentation on such special system roles. Note that currently most out-of-the-box metrics first rely on the helpers
  as v10 is relatively new still, and only when fetching fails, direct access with the "Privileged SQL" is tried.

* For gathering OS statistics (CPU, IO, disk) there are helpers and metrics provided, based on the "psutil" Python
  package...but from user reports seems the package behaviour differentiates slightly based on the Linux distro / Kernel
  version used, so small adjustments might be needed there (e.g. remove a non-existen column). Minimum usable Kernel version
  required is 3.3. Also note that SQL helpers functions are currently defined for Python 3, so for older Python 2 you need
  to change the ``LANGUAGE plpython3u`` part.

Running with developer credentials
----------------------------------

As mentioned above, helper / wrapper functions are not strictly needed, they just provide a bit more information for unprivileged users - thus for developers
with no means to install any wrappers as superuser it's also possible to benefit from pgwatch2 - for such use cases e.g.
the "unprivileged" preset metrics profile and the according "DB overview Unprivileged / Developer" `dashboard <https://raw.githubusercontent.com/cybertec-postgresql/pgwatch2/master/screenshots/overview_developer.png>`_
is a good starting point as it only assumes existence of `pg_stat_statements` which is available at all cloud providers.


Different *DB types* explained
------------------------------

When adding a new "to be monitored" entry a *DB type* needs to be selected. Following types are available:

*postgres*
  Monitor a single database on a single node.
  When using the Web UI and "DB name" field is left empty, then as a one time operation, all non-template DB names are fetched,
  prefixed with "Unique name" field value and added to monitoring (if not already monitored). Internally monitoring always
  happens "per DB" not "per cluster".

*postgres-continuous-discovery*
  Monitor a whole (or subset of DB-s) of Postgres cluster / instance.
  Host information without a DB name needs to be specified and then the pgwatch2 daemon will periodically scan the cluster
  and add any found and not yet monitored  DBs to monitoring. In this mode it's also possible to specify regular expressions
  to include/exclude some database names.

*pgbouncer*
  Use to track metrics from PgBouncer's "SHOW STATS" command.
  In place of the Postgres "DB name" the name of a PgBouncer "pool" to be monitored must be inserted.

*pgpool*
  Use to track joint metrics from Pgpool2's *SHOW POOL_NODES* and *POOL_PROCESSES* commands.
  Pgpool2 from version 3.0 is supported.

*patroni*
  Patroni is a HA / cluster manager for Postgres that relies on a DCS (Distributed Consensus Store) to store it's state.
  Typically in such a setup the nodes come and go and also it should not matter who is currently the master.
  To make it easier to monitor such dynamic constellations pgwatch2 supports reading of cluster node info from all
  supported DCS-s (etcd, Zookeeper, Consul), but currently only for simpler cases with no security applied (which is actually
  the common case in a trusted environment).

*patroni-continuous-discovery*
  As normal *patroni* DB type but all DB-s (or only those matching the regex if any provided) are monitored.

NB! All "continuous" modes expect access to "template1" or "postgres" databasess of the specified cluster to determine
the database names residing there.
