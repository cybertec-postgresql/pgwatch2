.. _custom_metrics:

Defining custom metrics
=======================

There's a good set of pre-defined metrics & metric configs provided by the pgwatch2 project to cover all typical needs,
but when monitoring hundreds of hosts you'd typically want to develop custom *preset configs* and maybe adjust the intervals
to reduce the data amounts.

General things to note about the built-in metrics:

* Only a half of them are included in the *Preset configs* and ready for direct usage. The others needs some extra
  extensions or privileges, OS level tool installations etc.

* Some builtin metrics are marked to be only executed when server is a primary or conversely, a standby. The flags can be
  inspected / set on the Web UI Metrics tab or in YAML mode by suffixing the metric definition with "standby" or "master".

* The "change_events" built-in metric used for detecting DDL & config changes uses internally some other "\*\_hashes" metrics
  which are not meant to be used on their own. Such metrics are marked also accordingly via the Web UI and they should not
  be removed.

Metric definitions
------------------

Metrics are named SQL queries that can return pretty much everything you find
useful and which can have different query text versions for different target PostgreSQL versions, also optionally taking
into account primary / replica state and as of v1.8 also versions of installed extensions.
Correct version of the metric definition will be chosen automatically by regularly connecting to the
target database and checking the Postgres version and if the monitoring user is a superuser or not. For superusers some
metrics are re-defined (v1.6.2) so that no "helpers" are needed for Postgres-native Stats Collector infos. Using superuser
accounts for monitoring is of course not really recommended.

Defining metrics
----------------

For defining metrics definitions you should adhere to a couple of basic concepts though:

* Every metric query should have an "epoch_ns" (nanoseconds since epoch column to record the metrics reading time.
  If the column is not there, things will still work but server timestamp of the metrics gathering daemon will be used,
  some a small loss (assuming intra-datacenter monitoring with little lag) of precision occurs.

* Queries can only return text, integer, boolean or floating point (a.k.a. double precision) Postgres data types. Note
  that columns with NULL values are not stored at all in the data layer as it's a bit bothersome to work with NULLs!

* Columns can be optionally "tagged" by prefixing them with "tag\_". By doing this, the column data
  will be indexed by the InfluxDB / Postgres giving following advantages:

  * Sophisticated auto-discovery support for indexed keys/values, when building charts with Grafana.

  * Faster queries for queries on those columns.

  * Less disk space used for repeating values in InfluxDB. Thus when you’re for example returning some longish
    and repetitive status strings (possible with Singlestat or Table panels) that you’ll be looking
    up by some ID column, it might still make sense to prefix the column with "tag\_" to reduce disks space.

  * If using InfluxDB storage, there needs to be at least one tag column, identifying all rows uniquely, is more than
    on row can be returned by the query.

* Fixed per host "custom tags" are also supported - these can contain any key-value data important to user and are
  added to all captured data rows

* For Prometheus the numerical columns are by default mapped to a Value Type of "Counter" (as most Statistics
  Collector columns are cumulative), but when this is not the case and the column is a "Gauge" then according column
  attributes should be declared. See below section on column attributes for details.

* NB! For Prometheus all text fields will be turned into tags / labels as only floats can be stored!

**Adding and using a custom metric:**

For *Config DB* based setups:

  #. Go to the Web UI "Metric definitions" page and scroll to the bottom.

  #. Fill the template - pick a name for your metric, select minimum supported PostgreSQL version and insert the query
     text and any extra attributes if any (see below for options). Hit the "New" button to store.

  #. Activate the newly added metric by including it in some existing *Preset Config* (listed on top of the page) or
     add it directly in JSON form, together with an interval, into the "Custom metrics config" filed on the "DBs" page.

For *YAML* based setups:

  #. Create a new folder for the metric under "/etc/pgwatch2/metrics". The folder name will be the metric's name, so choose
     wisely.

  #. Create a new subfolder for each "minimally supported Postgres version* and insert the metric's SQL definition into a
     file named "metric.sql". NB! Note the "minimally supported" part - i.e. if your query will work from version v9.0 to
     v13 then you only need one folder called "9.0". If there was a breaking change in the internal catalogs at v9.6 so
     that the query stopped working, you need a new folder named "9.6" that will be used for all versions above v9.5.

  #. Activate the newly added metric by including it in some existing *Preset Config* (/etc/pgwatch2/metrics/preset-configs.yaml)
     or add it directly to the YAML config "custom_metrics" section.

FYI - another neat way to quickly test if the metric can be successfully executed on the "to be monitored" DB is to launch
pgwatch2 in *ad-hoc mode*:

  ::

    pgwatch2-daemon \
      --adhoc-config='{"my_new_metric": 10}' --adhoc-conn-str="host=mytestdb dbname=postgres" \
      --datastore=postgres --pg-metric-store-conn-str=postgresql://... \
      --metrics-folder2=/etc/pgwatch2/metrics --verbose=info

Metric attributes
-----------------

Since v1.7 behaviour of plain metrics can be extended with a set of attributes that will modify the gathering in some way.
The attributes are stored in YAML files called *metric_attrs.yaml" in a metrics root directory or in the *metric_attribute*
Config DB table.

Currently supported attributes:

*is_instance_level*
  Enables caching, i.e. sharing of metric data between various databases of a single instance to
  reduce load on the monitored server.

*metric_storage_name*
  Enables dynamic "renaming" of metrics at storage level, i.e. declaring almost similar metrics
  with different names but the data will be stored under one metric. Currently used (for out-of-the box metrics) only
  for the 'stat_statements_no_query_text' metric, to not to store actual query texts from the "pg_stat_statements"
  extension for more security sensitive instances.

*extension_version_based_overrides*
  Enables to "switch out" the query text from some other metric based on some specific extension version. See 'reco_add_index' for an example definition.

*disabled_days*
 Enables to "pause" metric gathering on specified days. See metric_attrs.yaml for "wal" for an example.

*disabled_times*
  Enables to "pause" metric gathering on specified time intervals. e.g. "09:00-17:00" for business hours.
  Note that if time zone is not specified the server time of the gather daemon is used.
  NB! disabled_days / disabled_times can also be defined both on metric and host (host_attrs) level.

For a sample definition see `here <https://github.com/cybertec-postgresql/pgwatch2/blob/master/pgwatch2/metrics/wal/metric_attrs.yaml>`_.

Column attributes
-----------------

Besides the *\_tag* column prefix modifier, it's also possible to modify the output of certain columns via a few attributes. It's only
relevant for Prometheus output though currently, to set the correct data types in the output description, which is generally
considered a nice-to-have thing anyways. For YAML based setups this means adding a "column_attrs.yaml" file in the metric’s
top folder and for Config DB based setup an according "column_attrs" JSON column should be filled via the Web UI.

Supported column attributes:

*prometheus_ignored_columns*
  Columns to be discarded on Prometheus scrapes.

*prometheus_gauge_columns*
  Describe the mentioned output columns as of TYPE *gauge*, i.e. the value can change any time in any direction. Default
  TYPE for pgwatch2 is *counter*.

*prometheus_all_gauge_columns*
  Describe all columns of metrics as of TYPE *gauge*.

Adding metric fetching helpers
------------------------------

As mentioned in :ref:`Helper Functions <helper_functions>` section, Postgres knows very little about the Operating System that it's running on,
so in some (most) cases it might be advantageous to also monitor some basic OS statistics
together with the PostgreSQL ones, to get a better head start when troubleshooting performance problems. But as setup of
such OS tools and linking the gathered data is not always trivial, pgwatch2 has a system of *helpers* for fetching such data.

One can invent and install such *helpers* on the monitored databases freely to expose any information needed (backup status etc)
via Python, or any other PL-language supported by Postgres, and then add according metrics similarly to any normal Postgres-native metrics.
