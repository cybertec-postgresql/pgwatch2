.. :preparing_databases_for_monitoring:

Preparing databases for monitoring
==================================

Especially for remote, unprivileged monitoring users the operator / DBA is recommended to take some steps on the "to be monitored"
database to get maximum value out of pgwatch2. Without any custom configuration you lose though only about 10% of built-in metrics,
so nothing tragical also.

* As a base requirement you'll need a login user (non-superuser suggested) for connecting to your server and fetching metrics queries.
NB! Though theoretically you can use any username you like, but if not using "pgwatch2" you need to adjust the "helper" creation
SQL scripts accordingly as in those by default only the "pgwatch2" will be granted execute privileges.
```
CREATE ROLE pgwatch2 WITH LOGIN PASSWORD 'secret';
-- NB! For very important databases it might make sense to ensure that the user
-- account used for monitoring can only open a limited number of connections (there are according checks in code also though)
ALTER ROLE pgwatch2 CONNECTION LIMIT 3;
GRANT pg_monitor TO pgwatch2;   // v10+
```
* If monitoring below v10 servers and not using superuser and don't also want to grant "pg_monitor" to the monitoring user,
define the helper function to enable monitoring of some "protected" internal information, like active sessions info. If
using a superuser login (not recommended for remote "pulling", but only "pushing") you can skip this step. Note that there
might not be an exact Postgres version match for your helper, then replace $pgver with the next smallest version number
for the respective helper.

```
psql -h mydb.com -U superuser -f pgwatch2/metrics/00_helpers/$pgver/get_stat_activity/$pgver/metrics.sql mydb
```

* Additionally for extra insights ("Stat statements" dashboard and CPU load) it's also recommended to install the `pg_stat_statement`
contrib extension (Postgres 9.2+ needed to be useful for pgwatch2) and the PL/Python language. The latter one though is usually disabled
by DB-as-a-service providers for security reasons. For maximum pg_stat_statement benefit ("Top queries by IO time" dashboard),
one should also then enable the [track_io_timing](https://www.postgresql.org/docs/current/static/runtime-config-statistics.html#GUC-TRACK-IO-TIMING) setting.

```
# add pg_stat_statements to your postgresql.conf and restart the server
shared_preload_libraries = 'pg_stat_statements'
```
After restarting the server install the extensions as superuser
```
CREATE EXTENSION pg_stat_statements;
CREATE EXTENSION plpython3u;
```

Now also install the wrapper functions (under superuser role) for enabling "Stat statement" and CPU load info fetching for non-superusers
```
psql -h mydb.com -U superuser -f pgwatch2/metrics/00_helpers/get_stat_statements/$pgver/metrics.sql mydb
psql -h mydb.com -U superuser -f pgwatch2/metrics/00_helpers/get_load_average/$pgver/metrics.sql mydb
```

For more detailed statistics (OS monitoring, table bloat, WAL size, etc) it is recommended to install also all other helpers
found from the `pgwatch2/metrics/00_helpers` folder or do it automatically by using the rollout_helper.py script found in 00_helpers folder.
As of v1.6.0 though helpers are not needed for Postgres-native metrics (e.g. WAL size) if a privileged user (superuser or has pg_monitor GRANT)
is used as all Postres-protected metrics have also "privileged" SQL-s defined for direct access. Another good way to take
ensure that helpers get installed is to 1st run as superuser, by checking the `Auto-create helpers?` checkbox
(or "is_superuser: true" in YAML mode) when configuring databases and then switch to the normal unprivileged "pgwatch2" user.

NB! When rolling out helpers make sure the `search_path` is set correctly (same as monitoring role's) as metrics using the
helpers, assume that monitoring role's `search_path` includes everything needed i.e. they don't qualify any schemas.


Notice on using metric fetching helpers
---------------------------------------

* When installing some "helpers" and laters doing a binary PostgreSQL upgrade via `pg_upgrade`, this could result in some
error messages thrown. Then just drop those failing helpers on the "to be upgraded" cluster and re-create them after the upgrade process.

* Starting from Postgres v10 helpers are mostly not needed (only for PL/Python ones getting OS statistics) - there are available
some special monitoring roles like "pg_monitor", that are exactly meant to be used for such cases where we want to give access
to all Statistics Collector views without any other "superuser behaviour". See [here](https://www.postgresql.org/docs/current/default-roles.html)
for documentation on such special system roles. Note that currently most out-of-the-box metrics first rely on the helpers
as v10 is relatively new still, and only when fetching fails, direct access with the "Privileged SQL" is tried.

* For gathering OS statistics (CPU, IO, disk) there are helpers and metrics provided, based on the "psutil" Python
package...but from user reports seems the package behaviour differentiates slightly based on the Linux distro / Kernel
version used, so small adjustments might be needed there (e.g. remove a non-existen column). Minimum usable Kernel version
required is 3.3. Also note that SQL helpers functions are currently defined for Python 3, so for older Python 2 you need
to change the `LANGUAGE plpython3u` part.

# Running without helper / wrapper functions

Helpers/wrappers are not needed actually, they just provide a bit more information for unprivileged users - thus for developers
with no means to install any wrappers as superuser it's also possible to benefit from pgwatch2 - for such use cases e.g.
the "unprivileged" preset metrics profile and the according ["DB overview Unprivileged / Developer" dashboard](https://raw.githubusercontent.com/cybertec-postgresql/pgwatch2/master/screenshots/overview_developer.png)
is a good starting point as it only assumes existance of `pg_stat_statements` which is available at all cloud providers.






### Different "DB types" explained

* postgres - connect data to a single to-be-monitored DB needs to be specified. When using the Web UI and "DB name" field is left empty, then
as a one time operation, all non-template DB names are fetched, prefixed with "Unique name" field value and added to
monitoring (if not already monitored). Internally monitoring always happens "per DB" not "per cluster".
* postgres-continuous-discovery - connect data to a Postgres cluster (w/o a DB name) needs to be specified
and then the metrics daemon will periodically scan the cluster (connecting to the "template1" database,
which is expected to exist) and add any found and not yet monitored  DBs to monitoring. In this mode it's also possible to
specify regular expressions to include/exclude some database names.
* pgbouncer - use to track metrics from PgBouncer's "SHOW STATS" command. In place of the Postgres "DB name"
the name of a PgBouncer "pool" to be monitored must be inserted.
* patroni - Patroni is a HA / cluster manager for Postgres that relies on a DCS (Distributed Consensus Store) to store
it's state. Typically in such a setup the nodes come and go and also it should not matter who is currently the master.
To make it easier to monitor such dynamic constellations pgwatch2 supports reading of cluster node info from all
supported DCS-s (etcd, Zookeeper, Consul), but currently only for simpler cases with no security applied (which is actually
the common case in a trusted environment).
* patroni-continuous-discovery - as normal Patroni but all DB (or only those matching regex patterns) are monitored.

NB! "continuous" modes expect / need access to the "template1" DB of the specified cluster.