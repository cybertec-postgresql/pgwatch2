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

#. Run the Docker image, exposing minimally the Grafana port served on port 3000 internally. In a relatively secure
   environment you'd usually also include the administrative web UI served on port 8080:

   ::

     docker run -d --restart=unless-stopped -p 3000:3000 -p 8080:8080 --name pw2 cybertec/pgwatch2:X.Y.Z

   Note that we're using a Docker image with the built-in InfluxDB metrics storage DB here and setting the container to be automatically
   restarted in case of a reboot / crash - which is highly recommended if not using some container management framework to
   run pgwatch2.

.. _docker_example_launch:

More future proof setup steps
-----------------------------

Although the above simple setup example will do for more temporal setups / troubleshooting sessions, for permanent setups
it's highly recommended to create separate volumes for all software components in the container, so that it would be easier
to :ref:`update <upgrading>` to newer pgwatch2 Docker images and pull file system based backups and also it might be a good idea
to expose all internal ports at least on *localhost* for possible troubleshooting and making possible to use native backup
tools more conveniently for InfluxDB or Postgres.

Note that for maximum flexibility, security and update simplicity it's best to do a custom setup though - see the next
:ref:`chapter <custom_installation>` for that.

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

Also note that one can configure many aspects of the software components running inside the container via ENV - for a complete
list of all supported Docker environment variables see the `ENV_VARIABLES.md <https://github.com/cybertec-postgresql/pgwatch2/blob/master/ENV_VARIABLES.md>`_
file.

Available Docker images
-----------------------

Following images are regularly pushed to `Docked Hub <https://hub.docker.com/u/cybertec>`_:

*cybertec/pgwatch2*
  The original pgwatch2 "batteries-included" image with InfluxDB metrics storage. Just insert connect infos to your
  database via the admin Web UI (or directly into the Config DB) and then turn to the pre-defined Grafana dashboards
  to analyze DB health and performance.

*cybertec/pgwatch2-postgres*
  Exactly the same as previous, but metrics are also stored in PostgreSQL - thus needs more disk space. But in return you
  get more "out of the box" dashboards, as the power of standard SQL gives more complex visualization options.

*cybertec/pgwatch2-nonroot*
  Same components as for the original *cybertec/pgwatch2* image, but no "root" user is used internally, so it can also be
  launched in security restricted environments like OpenShift. Limits ad-hoc troubleshooting and "in container" customizations
  or updates though, but this is the standard for orchestrated cloud environments - you need to fix the image and re-deploy.

*cybertec/pgwatch2-daemon*
  A light-weight image containing only the metrics collection daemon / agent, that can be integrated into the monitoring
  setup over configuration specified either via ENV, mounted YAML files or a PostgreSQL Config DB. See the :ref:`Component
  reuse <component_reuse>` chapter for wiring details.

*cybertec/pgwatch2-db-bootstrapper*
  Sole purpose of the image is to bootstrap the pgwatch2 *Config DB* or *Metrics DB* schema. Useful for custom cloud oriented
  setups where the above "all components included" images are not a good fit.

Building custom Docker images
-----------------------------

For custom tweaks, more security,specific component versions, etc one could easily build the images themselves, just a
Docker installation is needed: `docker build .`.

Build scripts used to prepare the public images can be found `here <https://github.com/cybertec-postgresql/pgwatch2/blob/master/build-all-images-latest.sh>`__.


Interacting with the Docker container
-------------------------------------

* If to launch with the *PW2_TESTDB=1* env. parameter then the pgwatch2 configuration database running inside Docker
  is added to the monitoring, so that you should immediately see some metrics at least on the *Health-check* dashboard.

* To add new databases / instances to monitoring open the administration Web interface on port 8080 (or some other port,
  if re-mapped at launch) and go to the */dbs* page. Note that the Web UI is an optional component, and one can managed
  monitoring entries directly in the Postgres Config DB via INSERT-s / UPDATE-s into "pgwatch2.monitored_db" table. Default
  user/password are again *pgwatch2* / *pgwatch2admin*, database name - pgwatch2.
  In both cases note that it can take up to 2min (default main loop time, changeable via *PW2_SERVERS_REFRESH_LOOP_SECONDS*)
  before you see any metrics for newly inserted databases.

* One can edit existing or create new Grafana dashboards, change Grafana global settings, create users, alerts, etc after
  logging in as *admin* / *pgwatch2admin* (by default, changeable at launch time).

* Metrics and their intervals that are to be gathered can be customized for every database separately via a custom JSON
  config field or more conveniently by using *Preset Configs*, like "minimal", "basic" or "exhaustive" (monitored_db.preset_config
  table), where the name should already hint at the amount of metrics gathered. For privileged users the "exhaustive"
  preset is a good starting point, and "unprivileged" for simple developer accounts.

* To add a new metrics yourself (which are simple SQL queries returning any values and a timestamp) head to http://127.0.0.1:8080/metrics.
  The queries should always include a "epoch_ns" column and "tag\_" prefix can be used for columns that should be quickly
  searchable / groupable, and thus will be indexed with the InfluxDB and PostgreSQL metric stores. See to the bottom of the
  "metrics" page for more explanations or the documentation chapter on metrics :ref:`here <custom_metrics>`.

* For a quickstart on dashboarding, a list of available metrics together with some instructions are presented on the "Documentation" dashboard.

* Some built-in metrics like "cpu_load" and others, that gather privileged or OS statistics, require installing *helper functions*
  (looking like `that <https://github.com/cybertec-postgresql/pgwatch2/blob/master/pgwatch2/metrics/00_helpers/get_load_average/9.1/metric.sql>`_,
  so it might be normal to see some blank panels or fetching errors in the logs. On how to prepare databases for monitoring
  see the :ref:`Monitoring preparations <preparing_databases>` chapter.

* For effective graphing you want to familiarize yourself with the query language of the database system that was selected
  for metrics storage. Some tips to get going:

  * For InfluxQL -  the non_negative_derivative() function is very handy as Postgres statistics are mostly evergrowing counters
    and one needs to calculate so called *deltas* to show change. Documentation `here <https://docs.influxdata.com/influxdb/latest/query_language/functions/#non-negative-derivative>`__.

  * For PostgreSQL / TimescaleDB - some knowledge of `Window functions <https://www.postgresql.org/docs/current/tutorial-window.html>`_
    is a must if looking at longer time periods of data as the statistics could have been reset in the mean time by user request
    or the server might have crashed, so that simple *max() - min()* aggregates on cumulative counters (most data provided by Postgres is cumulative) would lie.

* For possible troubleshooting needs, logs of the components running inside Docker are by default (if not disabled on container launch) visible under:
  http://127.0.0.1:8080/logs/[pgwatch2|postgres|webui|influxdb|grafana]. It's of course also possible to log into the container
  and look at log files directly - they're situated under */var/log/supervisor/*.

  FYI - ``docker logs ...`` command is not really useful after a successful container startup in pgwatch2 case.


Ports used
----------

* 5432 - Postgres configuration or metrics storage DB (when using the cybertec/pgwatch2-postgres image)
* 8080 - Management Web UI (monitored hosts, metrics, metrics configurations)
* 8081 - Gatherer healthcheck / statistics on number of gathered metrics (JSON).
* 3000 - Grafana dashboarding
* 8086 - InfluxDB API (when using the InfluxDB version)
* 8088 - InfluxDB Backup port (when using the InfluxDB version)

Docker Compose
--------------

As mentioned in the :ref:`Components <components>` chapter, remember that the pre-built Docker images are just one
example how your monitoring setup around the pgwatch2 metrics collector could be organized. For another example how various
components (as Docker images here) can work together, see a *Docker Compose* example with loosely coupled components
`here <https://github.com/cybertec-postgresql/pgwatch2/blob/master/docker-compose.yml>`__.
