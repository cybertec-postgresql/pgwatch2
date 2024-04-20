#!/usr/bin/env bash
# the following is required to use alias psql within the script
shopt -s expand_aliases

# set -e

echo "db-boostrapper starting in $BOOTSTRAP_TYPE mode..."

echo "checking if target DB is online..."
for i in {1..100}; do
  OK=$(psql ${DATABASE_URL} -qXAtc "select 1" 2>/dev/null)
  if [ "$OK" == "1" ]; then
    echo "connection OK"
    break
  fi
  if [ $i -eq 100 ]; then
    echo "aborting. check PGHOST, PGPORT, etc."
    exit 1
  fi
  echo "connection NOT OK. sleeping 1s..."
  sleep 1
done

alias psql="psql ${DATABASE_URL} -v ON_ERROR_STOP=${ON_ERROR_STOP}"
###
### Rolls out Config DB or Metrics DB schemas on target DBs
###


# TODO override version dynamically based on ${BOOTSTRAP_TARGET_VERSION}
# wget https://github.com/cybertec-postgresql/pgwatch2/archive/v1.8.0.zip

if [ -z "$BOOTSTRAP_TYPE" ]; then
  echo "BOOTSTRAP_TYPE env expected. supported values: configdb | metricsdb"
  exit 1
fi

# BOOTSTRAP_TYPE: configdb | metricsdb
if [ $BOOTSTRAP_TYPE == "configdb" ]; then

psql -f /pgwatch2/sql/config_store/config_store.sql
psql -f /pgwatch2/sql/config_store/metric_definitions.sql

if [ "$BOOTSTRAP_ADD_TEST_MONITORING_ENTRY" == "1" ] || [ "$BOOTSTRAP_ADD_TEST_MONITORING_ENTRY" == "true" ]; then
SQL_INS=$(cat <<-EOF
insert into pgwatch2.monitored_db (md_unique_name, md_preset_config_name, md_hostname, md_port, md_dbname, md_user, md_password)
  select 'test', 'unprivileged', '$PGHOST', '$PGPORT', '$BOOTSTRAP_DATABASE', '$PGUSER', '$PGPASSWORD'
  on conflict do nothing;
EOF
)
echo "$SQL_INS" | psql -f-
fi

elif [ $BOOTSTRAP_TYPE == "metricsdb" ]; then

psql -f /pgwatch2/sql/metric_store/00_schema_base.sql
psql -f /pgwatch2/sql/metric_store/01_old_metrics_cleanup_procedure.sql

if [ "$BOOTSTRAP_METRICSDB_SCHEMA_TYPE" == "metric-dbname-time" ] ; then
  psql -f /pgwatch2/sql/metric_store/metric-dbname-time/metric_store_part_dbname_time.sql
  psql -f /pgwatch2/sql/metric_store/metric-dbname-time/ensure_partition_metric_dbname_time.sql
elif [ "$BOOTSTRAP_METRICSDB_SCHEMA_TYPE" == "metric-time" ] ; then
  psql -f /pgwatch2/sql/metric_store/metric-time/metric_store_part_time.sql
  psql -f /pgwatch2/sql/metric_store/metric-time/ensure_partition_metric_time.sql
elif [ "$BOOTSTRAP_METRICSDB_SCHEMA_TYPE" == "timescale" ] ; then
  psql -f /pgwatch2/sql/metric_store/timescale/change_chunk_interval.sql
  psql -f /pgwatch2/sql/metric_store/timescale/change_compression_interval.sql
  psql -f /pgwatch2/sql/metric_store/timescale/ensure_partition_timescale.sql
  psql -f /pgwatch2/sql/metric_store/timescale/metric_store_timescale.sql
  # timescaledb also requires
  psql -f /pgwatch2/sql/metric_store/metric-time/ensure_partition_metric_time.sql
else
  echo "invalid metricsdb schema type (BOOTSTRAP_METRICSDB_SCHEMA_TYPE) specified. supported values: metric-time | metric-dbname-time | timescale"
  exit 1
fi

fi

echo "db-boostrapper ($BOOTSTRAP_TYPE mode) finished"

# sleep 3600

exit 0
