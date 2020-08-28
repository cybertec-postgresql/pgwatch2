.. _upgrading:

Upgrading
=========

The pgwatch2 daemon code doesn't need too much maintenance itself (if you're not interested in new features), but the preset
metrics, dashboards and the other components that pgwatch2 relies, like Grafana, are under very active development and get
updates quite regularly so already purely from the security standpoint it would make sense to stay up to date.

We also regularly include new component versions in the Docker images after verifying that they work. If using Docker, you
could also choose to build your own images any time some new component versions are released, just increment the version
numbers in the Dockerfile.

Updating to a newer Docker version
----------------------------------

Without volumes
~~~~~~~~~~~~~~~

If pgwatch2 container was started in the simplest way possible without volumes, and if previously gathered metrics are
not of great importance, and there are no user modified metric or dashboard changes that should be preserved, then the easiest
way to get the latest components would be just to launch new container and import the old monitoring config:

::

  # let's backup up the monitored hosts
  psql -p5432 -U pgwatch2 -d pgwatch2 -c "\copy monitored_db to 'monitored_db.copy'"

  # stop the old container and start a new one ...
  docker stop ... && docker run ....

  # import the monitored hosts
  psql -p5432 -U pgwatch2 -d pgwatch2 -c "\copy monitored_db from 'monitored_db.copy'"

If metrics data and other settings like custom dashboards need to be preserved then some more steps are needed, but basically
it's about pulling InfluxDB / Postgres backups and restoring them into the new container - see the take_backup.sh
`script <https://github.com/cybertec-postgresql/pgwatch2/blob/master/take_backup.sh>`__ for an example with InfluxDB storage.

A tip: to make the restore process easier it would already make sense to mount the host folder with the backups in it on the
new container with "-v ~/pgwatch2_backups:/pgwatch2_backups:rw,z" when starting the Docker image. Otherwise one needs to set
up SSH or use something like S3 for example. Also note that ports 5432 and 8088 need to be exposed to take backups
outside of Docker for Postgres and InfluxDB respectively.

With volumes
~~~~~~~~~~~~

To make updates a bit easier, the preferred way to launch pgwatch2 should be to use Docker volumes for each individual
component - see the :ref:`Installing using Docker <docker_example_launch>` chapter for details. Then one can just stop the old
container and start a new one, re-using the volumes.

With some releases though, updating to newer version might additionally still require manual rollout of Config DB *schema migrations scripts*,
so always check the release notes for hints on that or just go to the "pgwatch2/sql/migrations" folder and execute all SQL
scripts that have a higher version than the old pgwatch2 container. Error messages like will "missing columns" or "wrong datatype"
will also hint at that, after launching with a new image. FYI - such SQL "patches" are generally not provided for metric updates,
nor dashboard changes and they need to be updated separately.


Updating without Docker
-----------------------

For a custom installation there's quite some freedom in doing updates - as components (Grafana, InfluxDB, PostgreSQL) are
loosely coupled, they can be updated any time without worrying too much about the other components. Only "tightly coupled" components are the
pgwatch2 metrics collector, config DB and the optional Web UI - if the pgwatch2 config is kept in the database. If YAML based
approach (see details :ref:`here <yaml_setup>`) is used, then things are even more simple - the pgwatch2 daemon can be updated
any time as YAML schema has default values for everything and there are no other "tightly coupled" components like the Web UI.

Updating Grafana
----------------

The update process for Grafana looks pretty much like the installation so take a look at the according :ref:`chapter <custom_install_grafana>`.
If using Grafana's package repository it should happen automatically along with other system packages. Grafana has a built-in
database schema migrator, so updating the binaries and restarting is enough.

Updating Grafana dashboards
---------------------------

There are no update or migration scripts for the built-in Grafana dashboards as it would break possible user applied changes. If
you know that there are no user changes, then one can just delete or rename the existing ones in a bulk matter and import the latest JSON
definitions. See :ref:`here <dashboard_maintenance>` for some more advice on how to manage dashboards.

Updating the config / metrics DB version
----------------------------------------

Database updates can be quite complex, with many steps, so it makes sense to follow the manufacturer's instructions here.

For InfluxDB typically something like that is enough though (assuming Debian based here):

::

    influxd version # check current version
    INFLUX_LATEST=$(curl -so- https://api.github.com/repos/influxdata/influxdb/releases/latest \
                      | jq .tag_name | grep -oE '[0-9\.]+')
    wget https://dl.influxdata.com/influxdb/releases/influxdb_${INFLUX_LATEST}_amd64.deb
    sudo dpkg -i influxdb_${INFLUX_LATEST}_amd64.deb

For PostgreSQL one should distinguish between minor version updates and major version upgrades. Minor updates are quite
straightforward and problem-free, consisting of running something like:

::

    apt update && apt install postgresql
    sudo systemctl restart postgresql

For PostgreSQL major version upgrades one should read through the according release notes (e.g. `here <https://www.postgresql.org/docs/12/release-12.html#id-1.11.6.5.4>`__)
and be prepared for the unavoidable downtime.

Updating the pgwatch2 schema
----------------------------

This is the pgwatch2 specific part, with some coupling between the following components - Config DB SQL schema, metrics collector,
and the optional Web UI.

Here one should check from the `CHANGELOG <https://github.com/cybertec-postgresql/pgwatch2/blob/master/CHANGELOG.md>`__ if
pgwatch2 schema needs updating. If yes, then manual applying of schema diffs is required before running the new gatherer
or Web UI. If no, i.e. no schema changes, all components can be updated independently in random order.

Assuming that we initially installed pgwatch2 version v1.6.0, and now the latest version is 1.6.2, based on the release notes and
`SQL diffs <https://github.com/cybertec-postgresql/pgwatch2/tree/master/pgwatch2/sql/config_store/migrations>`__ we need to
apply the following files:

   ::

       psql -f /etc/pgwatch2/sql/config_store/migrations/v1.6.1-1_patroni_cont_discovery.sql pgwatch2
       psql -f /etc/pgwatch2/sql/config_store/migrations/v1.6.2_superuser_metrics.sql pgwatch2

Updating the metrics collector
------------------------------

Compile or install the gatherer from RPM / DEB / tarball packages. See the :ref:`Custom installation <custom_installation>`
chapter for details.

If using a SystemD service file to auto-start the collector then you might want to also check for possible updates on the
template there - */etc/pgwatch2/startup-scripts/pgwatch2.service*.

Updating the Web UI
-------------------

Update the optional Python Web UI if using it to administer monitored DB-s and metric configs. The Web UI was not included
in the pre-built packages of older pgwatch2 versions as deploying self-contained Python that runs on all platforms is not
overly easy. If Web UI is started directly on the Github sources (`git clone && cd webpy && ./web.py`) then it is actually updated automatically as CherryPy
web server monitors the file changes. If there were some breaking schema changes though, it might stop working and needs
a restart after applying schema "diffs" (see above).

If using a SystemD service file to auto-start the Web UI then you might want to also check for possible updates on the
template there - */etc/pgwatch/webpy/startup-scripts/pgwatch2-webui.service*.

.. _updating_metrics:

Updating metric definitions
---------------------------

In the YAML mode you always get new SQL definitions for the built-in metrics automatically when refreshing the sources via Github
or pre-built packages, but with Config DB approach one needs to do it manually. Given that there are no user added metrics,
it's simple enough though - just delete all old ones and re-insert everything from the latest metric definition SQL file.

::

   pg_dump -t pgwatch2.metric pgwatch2 > old_metric.sql  # a just-in-case backup
   psql  -c "truncate pgwatch2.metric" pgwatch2
   psql -f /etc/pgwatch2/sql/config_store/metric_definitions.sql pgwatch2

**NB! If you have added some own custom metrics be sure not to delete or truncate them!**
