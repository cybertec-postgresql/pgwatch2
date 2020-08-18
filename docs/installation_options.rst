Installation options
====================

Besides freedom of choosing from a set of metric storage options one can also choose how they're going to retrieve data
- in a "pull" (default) or "push" way and how is the monitoring configuration (connect strings, metric sets and intervals)
going to be stored.

Config DB based operation
-------------------------

This is the original central pull mode depicted on the :ref:`architecture diagram <typical_architecture>`. It requires a
small schema to be rolled out on any Postgres database accessible to the metrics gathering daemon, which will hold the
connect strings, metric definition SQL-s and preset configurations and some other more minor attributes. For rollout details
see the :ref:`custom installation <custom_installation>` chapter.


File based operation
--------------------

From v1.4.0 one can deploy the gatherer daemon(s) decentrally with *hosts to be monitored* defined in simple YAML files.
In that case there is no need for the central Postgres "config DB". See the sample `instances.yaml <https://github.com/cybertec-postgresql/pgwatch2/blob/master/pgwatch2/config/instances.yaml>`_
config file to get started. Note that in this mode you also need to point out the folder of metric definition SQL files
when starting the gatherer. Also note that the configuration system also supports multiple YAML files in a folder so that
you could easily programmatically manage things via *Ansible* for example.

Relevant Gatherer env. vars / flags: ``--config, --metrics-folder`` or ``PW2_CONFIG / PW2_METRICS_FOLDER``.


Ad-hoc mode
-----------

Optimized for Cloud scenarios and quick temporary setups, it's also possible to run the metrics gathering daemon in a somewhat
limited "ad-hoc" mode, by specifying a single connection string via ENV or command line input and plus the same for the metrics
and intervals (as a JSON string) or a preset config name. It's also possible to choose if monitoring only the specified DB
(the default behaviour) or the whole cluster.

This mode is perfect also for Cloud setups in *sidecar* constellations when exposing the Prometheus output. Pushing to a central
metrics DB is also a good option still if the monitoring details like intervals etc are static enough.

In that case there is no need for the central Postgres "config DB" nor the YAML config file specifying which hosts to monitor.
NB! When using that mode with the default Docker image, the built-in metric definitions can't be changed via the Web UI.

Relevant Gatherer env. vars / flags: ``--adhoc-conn-str, --adhoc-config, --adhoc-name, --metrics-folder`` or respectively
``PW2_ADHOC_CONN_STR, PW2_ADHOC_CONFIG, PW2_ADHOC_NAME, PW2_METRICS_FOLDER, PW2_ADHOC_CREATE_HELPERS``.

::

    # launching in ad-hoc / test mode
    docker run --rm -p 3000:3000 -e PW2_ADHOC_CONN_STR="postgresql://user:pwd@mydb:5432/mydb1" \
        -e PW2_ADHOC_CONFIG=unprivileged --name pw2 cybertec/pgwatch2-postgres

    # launching in ad-hoc / test mode, creating metrics helpers automatically (requires superuser)
    docker run --rm -p 3000:3000 -e PW2_ADHOC_CONN_STR="postgresql://user:pwd@mydb:5432/mydb1" \
        -e PW2_ADHOC_CONFIG=exhaustive -e PW2_ADHOC_CREATE_HELPERS=true --name pw2 cybertec/pgwatch2-postgres

NB! Using the ``PW2_ADHOC_CREATE_HELPERS`` flag will try to create all metrics fetching helpers automatically if not already
existing - this assumes superuser privileges though, which is not recommended for long term setups for obvious reasons.
In case a long term need rises it's recommended to change the monitoring role to an unprivileged *pgwatch2* user, which
by default gets execute *GRANT*-s to all helper functions. More details on secure setups can be found in the :ref:`security chapter <security>`.

Prometheus mode
---------------

In v1.6.0 was added support for Prometheus - being one of the most popular modern metrics gathering / alerting solutions.
When the ``--datastore / PW2_DATASTORE`` parameter is set to *prometheus* then the pgwatch2 metrics collector doesn't do any normal interval-based fetching but
listens on port *9187* (changeable) for scrape requests configured and performed on Prometheus side. Returned metrics belong
to "pgwatch2" namespace (a prefix basically) and is changeable via the ``--prometheus-namespace`` flag.

Also important to note - in this mode the pgwatch2 agent should not be run centrally but on all individual DB hosts. While
technically possible though to run centrally, it would counter the core idea of Prometheus and would make scrapes also longer
as risk getting timeouts as all DBs are scanned sequentially for metrics.

FYI – the functionality has some overlap with the existing `postgres_exporter <https://github.com/wrouesnel/postgres_exporter>`_
project but also provides more flexibility in metrics configuration and all config changes are applied "online".

Also note that Prometheus can only store numerical metric data values so not all metrics produce same values as for example
with PostgreSQL storage - due to that there's also a separate "preset config" named "prometheus".
