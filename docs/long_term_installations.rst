Long term installations
=======================

For long term setups there are a couple of general recommendations that need some occasional care:

Updating the pgwatch2 collector
-------------------------------

This is the core and most critical component of pgwatch2 so it's definitely recommended
to update at least once per year, as with Postgres :) See below sections for details but basically the process is very
similar to initial installing, as the collector doesn't have any state on its own. See more details in the according
:ref:`chapter <upgrading>`.

Keeping inventory in sync
-------------------------

Adding new DBs to monitoring and removing those shut down can become a problem if teams are big, databases are many, and
it's done per hand (talking about on-premise, non-orchestrated deployments). To combat that the most typical approach would
be to write some script / Crons that parse the company's internal inventory database, files or endpoints and translate changes
to according CRUD operations on the *pgwatch2.monitored_db* table directly. One could also use the Web UI page (pseudo) *API*
for that purpose, if using the Web UI anyways. See `here <https://github.com/cybertec-postgresql/pgwatch2/blob/master/docker/test/smoke_test_docker_image.sh#L44>`_
for an example, but direct access is of course more flexible. If pgwatch2 config is kept in YAML files, it should be relatively
easy to automate it's maintenance in the same way as one file can represent a single entry.

Metrics maintenance
-------------------

Some metrics (SQL) are regularly corrected as suggestions / improvements come in and new ones are also added mostly due
to new metrics being added in latest PG versions. So 1-2x per year would make sense to delete (backups!) the initial ones and import
new ones from the definition [file](https://github.com/cybertec-postgresql/pgwatch2/blob/master/pgwatch2/sql/config_store/metric_definitions.sql)
or update them "metrics" [folder](https://github.com/cybertec-postgresql/pgwatch2/tree/master/pgwatch2/metrics) when using the YAML setup.

NB! If you add your own custom metrics make sure not to delete them!

Dashboard maintenance
---------------------

Couple of times a year also main dashboards get updates, so same as with metrics - makes sense to refresh them occasionally.
The delete / import scripts are [here](https://github.com/cybertec-postgresql/pgwatch2/tree/master/grafana_dashboards).

NB! As the scripts by default first delete all pgwatch2 created dashboards, you should take care when you've changed them -
which is a typical thing to do actully. So a good idea is to rename the dashboards you've changed to something else.

Storage monitoring
------------------

In addition to all that you should at least initially periodically monitor the metrics DB size...as it can grow quite a
lot (especially when using Postgres for storage) based on how many tables / indexes and unique SQL-s are used. If it grows
too fast one can increase the metric intervals (especially for "stat_statements" and "table_stats") or decrease the data
retention time (--pg-retention-days or --iretentiondays params).
