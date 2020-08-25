.. _upgrading:

Updating to a newer Docker version
==================================

pgwatch2 code part doesn't need too much maintenance itself (most issues seem to be related to dashboards that users
can actually change themselves) but the main components that pgwatch2 relies on (Grafana, InfluxDB)
are pretty active and get useful features and fixes quite regularly, thus we'll also try to push new 'latest' images,
so it would make sense to check for updates time to time on `Docker Hub <https://hub.docker.com/r/cybertec/pgwatch2/tags/>`__.
NB! You could also choose to build your own image any time and the build scripts will download the latest components for you.

If possible (e.g. previously gathered metrics are not important and there are no user added dashboard/graphs)
then the easiest way to get the latest Docker image would be just to stop the old one and doing 'docker pull/run'
again as described in beginning of the README.

If using a custom setup, switching out single components should be quite easy, just follow the component provider's
instructions. Migrating data from the current Docker container to a newer version of the pgwatch2 Docker
image on the other hand needs quite some steps currently. See the take_backup.sh script
`here <https://github.com/cybertec-postgresql/pgwatch2/blob/master/take_backup.sh>`__ for more details. To make updates a
bit easier, the preferred way should be though to think about it previously and use Docker volumes accordingly - see the
Dockerfile for details. On some rare occasions updating to newer pgwatch2 Web UI or gahterer daemon might additionally
still require rollout of some manual config DB schema migrations scripts from the "migrations" subfolder - error messages
will include "missing columns" or "wrong datatype" then. SQL "patches" might be provided also for important metric updates,
but for dashboard changes there will be none - users need to import them from JSON directly!

Basically there are two options – first, go into the Docker container (e.g. *docker exec -it pw2 /bin/bash*)
and just update the component yourself – i.e. download the latest Grafana .deb package and install it with "dpkg -i …".
This is actually the simplest way. The other way would be to fetch the latest pgwatch2 image, which already has the
latest version of components, using "docker pull" and then restore the data (InfluxDB + Postgres) from a backup of old
setup. For restoring one needs to go inside the Docker container again but by following the steps described in
take_backup.sh it shouldn't be a real problem.

A tip: to make the restore process easier it would already make sense to mount the host folder with the backups in it on the
new container with "-v ~/pgwatch2_backups:/pgwatch2_backups:rw,z" when starting the Docker image. Otherwise one needs to set
up SSH or use something like S3 for example. Also note that ports 5432 and 8088 need to be exposed to take backups
outside of Docker.


Updating without Docker
-----------------------

For a custom installation there's quite some freedom in doing updates - fully independent components (Grafana, InfluxDB, PostgreSQL)
can be updated any time without worrying too much about the other components. Only "tightly coupled" components are the
pgwatch2 metrics collector, config DB and the optional Web UI - if the pgwatch2 config is kept in the database. If YAML
approach (see the "File based operation" paragraph above) is used then things are more simple - the collector can be updated
any time as YAML schema has default values for everything and also there's no Web UI (and Config DB = YAML files) and
there order of component updates doesn't matter.

Updating Grafana
----------------

The update process for Grafana looks pretty much like the installation so take a look at the according :ref:`chapter <custom_install_grafana>`.
If using Grafana's package repository it should happen automatically via *apt upgrade*.

NB! There are no update scripts for the "preset" Grafana dashboards as it would break possible user applied changes. If
you know that there are no user changes then one can just delete or rename the existing ones and import the latest JSON
definitions from `here <https://github.com/cybertec-postgresql/pgwatch2/tree/master/grafana_dashboards>`__. Also note that
the dashboards don't change too frequently so it only makes sense to update if you haven't updated them for half a year
or more, or if you pick up see some change decriptions from the `CHANGELOG <https://github.com/cybertec-postgresql/pgwatch2/blob/master/CHANGELOG.md>`__.

Updating the config / metrics DB version
----------------------------------------

Database updates can be quite complex, with many steps, so it makes sense to follow the manufacturer's instructions here.

For InfluxDB typically something like that is enough though (assuming Debian based distros):

::

    influx -version # check current version
    VER=$(curl -so- https://api.github.com/repos/influxdata/influxdb/tags | grep -Eo '"v[0-9\.]+"' | grep -Eo '[0-9\.]+' | sort -nr | head -1)
    wget -q -O influxdb.deb https://dl.influxdata.com/influxdb/releases/influxdb_${VER}_amd64.deb
    dpkg -i influxdb.deb

For PostgreSQL one should distinguish between minor version updates and major version upgrades. Minor updates are quite
straightforward and problem-free, consisting of running something like (assuming Debian based distros):

::

    apt update && apt install postgresql
    sudo systemctl restart postgresql

For PostgreSQL major version upgrades one should read the according relase notes (e.g. `here <https://www.postgresql.org/docs/12/release-12.html#id-1.11.6.5.4>`__)
and be prepared for the unavoidable downtime.


Updating the pgwatch2 schema
----------------------------

This is the pgwatch2 specific part, with some coupling between the following components - SQL schema, metrics collector,
and the optional Web UI.

Here one should check from the `CHANGELOG <https://github.com/cybertec-postgresql/pgwatch2/blob/master/CHANGELOG.md>`__ if
pgwatch2 schema needs updating. If yes, then manual applying of schema diffs is required before running the new gatherer
or Web UI. If no, i.e. no schema changes, all components can be updated independently in random order.

1. Given that we initially installed pgwatch v1.6.0, and now the latest version is 1.6.2, based on the release notes and
`SQL diffs <https://github.com/cybertec-postgresql/pgwatch2/tree/master/pgwatch2/sql/config_store/migrations>`__ we need to
apply the following files:

   ::

       psql -U pgwatch2 -f pgwatch2/sql/config_store/migrations/v1.6.1-1_patroni_cont_discovery.sql pgwatch2
       psql -U pgwatch2 -f v1.6.2_superuser_metrics.sql pgwatch2

NB! When installing from packages the "diffs" are at: /etc/pgwatch2/sql/config_store/migrations/

Updating the metrics collector
------------------------------

2. Compile or install the gatherer from RPM / DEB / tarball packages. See the above "Installing without Docker" paragraph
for building details.

Updating the Web UI
-------------------

3. Update the optional Python Web UI if using it to administer monitored DB-s and metric configs. The Web UI is not in the
pre-built packages as deploying self-contained Python that runs on all platforms is not overly easy. If Web UI is started
directly on the Github sources (`git clone && cd webpy && ./web.py`) then it is actually updated automatically as CherryPy
web server monitors the file changes. If there were some breaking schema changes though, it might stop working and needs
a restart after applying schema "diffs".

4. If using SystemD service files to auto-start the collector or the Web UI, you might want to also check for possible
updates there - "webpy/startup-scripts/pgwatch2-webui.service" for the Web UI or "pgwatch2/startup-scripts/pgwatch2.service" (/etc/pgwatch2/startup-scripts/pgwatch2.service
for pre-built packages).

Updating metric definitions
---------------------------

5. Checking / updating metric definitions.

   In the YAML mode you always get it automatically when refreshing the sources via Github or pre-built packages, but with
   Config DB approach one needs to do it manually. Given that there are no user added metrics, is simple enough though - just delete
   all old ones and re-insert everything from the latest metric definition SQL file.

   ::

       pg_dump -t pgwatch2.metric pgwatch2 > old_metric.sql  # a just-in-case backup
       psql  -c "truncate pgwatch2.metric" pgwatch2
       psql -f /etc/pgwatch2/sql/config_store/metric_definitions.sql pgwatch2
