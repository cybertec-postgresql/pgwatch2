Sizing recommendations
===============================

* Min 1GB RAM required for the Docker setup. The gatherer alone needs typically less than 50 MB if the metrics store is online -
  otherwise metrics are cached in RAM up to a limit of 10k data points (for all databases) and then it's dependent on the metrics configuration.

* 2 GBs of disk space should be enough for monitoring 1 DB for 1 month with InfluxDB. 1 month is also the default metrics
  retention policy for Influx running in Docker (configurable). Depending on the amount of schema objects - tables, indexes, stored
  procedures and especially on number of unique SQL-s, it could be also much more. With Postgres as metric store multiply it with ~5x,
  but if disk size reduction is wanted for PostgreSQL storage then the simplest way is to use the TimescaleDB extension - it has
  built-in compression and disk footprint is on the same level with InfluxDB, while retaining full SQL support.
  There's also a "test data generation" mode in the collector to exactly determine disk footprint for your use case - see PW2_TESTDATA_DAYS and
  PW2_TESTDATA_MULTIPLIER params for that (requires also "ad-hoc" mode params).

* A low-spec (1 vCPU, 2 GB RAM) cloud machine can easily monitor 100 DBs in "exhaustive" settings (i.e. almost all metrics
  are monitored in 1-2min intervals) without breaking a sweat (<20% load). When a single node where the metrics collector daemon
  is running is becoming a bottleneck, one can also do "sharding" i.e. limit the amount of monitored databases for that node
  based on the Group label(s) (--group), which is just a string for logical grouping.

* A single InfluxDB node should handle thousands of requests per second but if this is not enough having a secondary/mirrored
  InfluxDB is also possible. If more than two needed (e.g. feeding many many Grafana instances or some custom exporting) one
  should look at Influx Enterprise (on-prem or cloud) or Graphite (which is also supported as metrics storage backend). For PostgreSQL
  metrics storage one could use streaming replicas for read scaling or for example Citus for write scaling.

* When high metrics write latency is problematic (e.g. using a DBaaS across the atlantic) then increasing the default maximum
  batching delay of 250ms(--batching-delay-ms / PW2_BATCHING_MAX_DELAY_MS) usually gives good results.

* Note that when monitoring a very large number of databases, it's possible to "shard" / distribute them between many
  metric collection instances running on different hosts, via the ``--group | PW2_GROUP`` flag / env, given that some hosts
  have been assigned a non-default group identifier which is just a text field exactly for this sharding purpose.