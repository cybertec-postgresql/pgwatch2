Installing using Docker
=======================

Simple setup steps
------------------

The simplest real-life pgwatch2 setup should look something like that:

#. Decide which metrics storage engine you want to use - *cybertec/pgwatch2* and *cybertec/pgwatch2-nonroot* images use InfluxDB
   internally for metrics storage, while *cybertec/pgwatch2-postgres* uses PostgreSQL. For Prometheus mode (exposing a port
   for remote scraping) one should use the slimmer *cybertec/pgwatch2-daemon* image which doesn't have any built in databases.
#. Find the latest pgwatch2 release version by going to the project's Github *Releases* page or use the public API with
   something like that:

   ::

     curl -so- https://api.github.com/repos/cybertec-postgresql/pgwatch2/releases/latest | jq .tag_name | grep -oE '[0-9\.]+'

#. Pull the image:

   ::

     docker pull cybertec/pgwatch2:X.Y.Z

#. Run the latest Docker image, exposing minimally the Grafana port served on port 3000 internally. In a relatively secure
   environment you'd usually also include the administrative web UI served on port 8080:

   ::

     docker run -d --restart=unless-stopped -p 3000:3000 -p 8080:8080 --name pw2 cybertec/pgwatch2:X.Y.Z

   Note that we're using a Docker image with built-in InfluxDB metrics storage DB here and setting the container to be automatically
   restarted in case of a reboot / crash, which is highly recommended if not using some container management framework to
   run pgwatch2.

.. _docker_example_launch:

More future proof setup steps
-----------------------------

Although the above simple setup example will do for more temporal setups / troubleshooting sessions, for permanent setups
it's highly recommended to create separate volumes for all software components in the container, so that it would be easier
to :ref:`update <upgrading>` to newer pgwatch2 Docker images and pull file system based backups and also it might be a good idea
to expose all internal ports to at least *localhost* for possible troubleshooting and making possible to use native backup
tools conveniently for InfluxDB or Postgres.

Note that for maximum flexibility, security and update simplicity it's best to do a custom setup though - see the next
:ref:`chapter <custom_installation` for that.

So in short, for plain Docker setups would be best to do something like:

::

  # let's create volumes for Postgres, Grafana and pgwatch2 marker files / SSL certificates
  for v in pg  grafana pw2 ; do docker volume create $v ; done

  # launch pgwatch2 with fully exposed Grafana and Health-check ports
  # and local Postgres and subnet level Web UI ports
  docker run -d --restart=unless-stopped --name pw2 \
    -p 3000:3000 -p 8081:8081 -p 127.0.0.1:5432:5432 -p 192.168.1.XYZ:8080:8080 \
    -v pg:/var/lib/postgresql -v grafana:/var/lib/grafana -v pw2:/pgwatch2/persistent-config \
    cybertec/pgwatch2-postgres:X.Y.Z

Note that in non-trusted environments it's a good idea to specify more sensitive ports together with some explicit network
interfaces for additional security - by default Docker listens on all network devices!

Also note that one can configure a lot of aspects of the software components running inside the container, so for a complete
list of all supported Docker environment variables see the `ENV_VARIABLES.md <https://github.com/cybertec-postgresql/pgwatch2/blob/master/ENV_VARIABLES.md>`_
file.


Building custom Docker images
-----------------------------

For custom tweaks, more security,specific component versions, etc one could easily build the images themselves, just a
Docker installation is needed: `docker build .`.

Build scripts used to prepare the public images can be found `here <https://github.com/cybertec-postgresql/pgwatch2/blob/master/build-all-images-latest.sh>`_.


Usage basics (Docker)
---------------------

* by default the "pgwatch2" configuration database running inside Docker is being monitored so that you can immediately see
  some graphs, but you should add new databases by opening the "admin interface" at 127.0.0.1:8080/dbs or logging into the
  Postgres config DB and inserting into "pgwatch2.monitored_db" table (db - pgwatch2 , default user/pw - pgwatch2/pgwatch2admin).
  Note that it can take up to 2min before you see any metrics for newly inserted databases.

* one can create new Grafana dashboards (and change settings, create users, alerts, ...) after logging in as "admin" (admin/pgwatch2admin)

* metrics (and their intervals) that are to be gathered can be customized for every database by using a preset config
like "minimal", "basic" or "exhaustive" (monitored_db.preset_config table) or a custom JSON config.

* to add a new metrics  yourself (simple SQL queries returing point-in-time values) head to http://127.0.0.1:8080/metrics.
The queries should always include a "epoch_ns" column and "tag_" prefix can be used for columns that should be tags
(thus indexed) in InfluxDB.

* a list of available metrics together with some instructions is also visible from the "Documentation" dashboard

* some predefine metrics (cpu_load, stat_statements) require installing helper functions (look into "pgwatch2/metrics/00_helpers" folder) on monitored DBs2

* for effective graphing you want to familiarize yourself with basic InfluxQL and the non_negative_derivative() function
which is very handy as Postgres statistics are mostly evergrowing counters. Documentation [here](https://docs.influxdata.com/influxdb/latest/query_language/functions/#non-negative-derivative).

* for troubleshooting, logs for the components are visible under http://127.0.0.1:8080/logs/[pgwatch2|postgres|webui|influxdb|grafana] or by logging
into the docker container under /var/logs/supervisor/


Docker Compose
--------------

ASasa