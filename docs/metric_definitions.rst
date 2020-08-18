# Adding metrics

## Note on built-in metrics

There's a good set of pre-defined metrics & configs provided (and installed when using the Docker image) that should cover most people's needs, but when monitoring dozens of hosts the intervals should be probably adjusted to reduce data amounts.

Things to note:

* Some builtin metrics are marked to be only executed when server is a primary or conversely, a standby. The flags can be inspected on the Web UI Metrics tab.
* The "change_events" builtin metric used for detecting DDL & config changes uses internally some other "*_hashes" metrics
which are not meant to be used on their own.

## Metric definitions

Metrics are named SQL queries that can return pretty much everything you find
useful and which can have different query text versions for different target PostgreSQL versions, also optionally taking
into account primary / replica state and as of v1.8 also versions of installed extensions.
Correct version of the metric definition will be chosen automatically by regularly connecting to the
target database and checking the Postgres version and if the monitoring user is a superuser or not. For superusers some
metrics are re-defined (v1.6.2) so that no "helpers" are needed for Postgres-native Stats Collector infos. Using superuser
accounts for monitoring is of course not really recommended.

For defining metrics definitions you should adhere to a couple of basic concepts though:

* Every metric query should have an “epoch_ns” (nanoseconds since epoch, default InfluxDB timestamp
precision) column to record the metrics reading time. If the column is not there, things will still
work though as gathering server’s timestamp will be used, you’ll just lose some milliseconds
(assuming intra-datacenter monitoring) of precision.
* Queries can only return text, integer, boolean or floating point (a.k.a. double precision) Postgres data types. Note
that columns with NULL values are not stored at all in the data layer as it's a bit bothersome to work with NULLs!
* Columns can be optionally “tagged” by prefixing them with “tag_”. By doing this, the column data
will be indexed by the InfluxDB / Postgres giving following advantages:
  * Sophisticated auto-discovery support for indexed keys/values, when building charts with Grafana.
  * Faster queries for queries on those columns.
  * Less disk space used for repeating values in InfluxDB. Thus when you’re for example returning some longish
  and repetitive status strings (possible with Singlestat or Table panels) that you’ll be looking
  up by some ID column, it might still make sense to prefix the column with “tag_” to reduce disks
  space.
* Fixed per host "custom tags" are also supported - these can contain any key-value data important to user and are
added to all captured data rows
* For Prometheus the numerical columns are by default mapped to a Value Type of "Counter" (as most Statistics
Collector columns are cumulative), but when this is not the case and the column is a "Gauge" then according column
attributes should be decalared. For YAML based setups this means adding a "column_attrs.yaml" file in the metric's
top folder and for Config DB based setup an according "column_attrs" JSON column should be filled.
* NB! For Prometheus all text fields will be turned into tags / labels as only floats can be stored.

### Metric attributes

Besides column attributes starting from v1.7 there are also metric attributes which enable currently two special behaviours
for some specific metrics:

 * is_instance_level - enables caching, i.e. sharing of metric data between various databases of a single instance to
   reduce load on the monitored server.
 * metric_storage_name - enables dynamic "renaming" of metrics at storage level, i.e. declaring almost similar metrics
   with different names but the data will be stored under one metric. Currently used (for out-of-the box metrics) only
   for the 'stat_statements_no_query_text' metric, to not to store actual query texts from the "pg_stat_statements"
   extension for more security sensitive instances.
* extension_version_based_overrides - enables to "switch out" the query text from some other metric based on some specific
  extension version. See 'reco_add_index' for an example definition.
* disabled_days - enables to "pause" metric gathering on specified days. See metric_attrs.yaml for "wal" for an example.
* disabled_times - enables to "pause" metric gathering on specified time intervals. e.g. "09:00-17:00" for business hours.
  NB! disabled_days / disabled_times can also be defined both on metric and host (host_attrs) level.


Metric fetching helpers
-----------------------


As mentioned in :ref:`Notice on using metric fetching helpers` sections, Postgres knows very little about the Operating
System that it's running on, so in some (most) cases it might be advantageous to also monitor some basic OS statistics
together with the PostgreSQL ones, to get a better head start when troubleshooting performance problems. But as setup of
such OS tools and linking the gathered data is not always trivial, pgwatch2 has a system of *helpers* for fetching such data.

Helper are basically .........