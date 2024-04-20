#!/usr/bin/env bash
# the following is required to use alias psql within the script
shopt -s expand_aliases

# set -e

echo "monitored-db-boostrapper starting ..."

echo "checking if target DB is online..."
for i in {1..100}; do
  OK=$(psql ${DATABASE_URL} -qXAtc "select 1" 2>/dev/null)
  if [ "$OK" == "1" ]; then
    echo "connection OK"
    break
  fi
  if [ $i -eq 100 ]; then
    echo "aborting. check DATABASE_URL, etc."
    exit 1
  fi
  echo "connection NOT OK. sleeping 1s..."
  sleep 1
done

alias psql="psql ${DATABASE_URL} -v ON_ERROR_STOP=${ON_ERROR_STOP}"
###
### Rolls out monitored db configuration
###

SQL_CMDS=$(cat <<-EOF
GRANT pg_monitor TO pgwatch2;
GRANT USAGE ON SCHEMA public TO pgwatch2;

EOF
)
echo "$SQL_CMDS" | psql -f-

psql -f /pgwatch2/metrics/00_helpers/get_stat_activity/9.2/metric.sql

psql -f /pgwatch2/metrics/00_helpers/get_stat_statements/9.4/metric.sql

psql -f /pgwatch2/metrics/00_helpers/get_stat_replication/9.2/metric.sql

echo "monitored-db-boostrapper finished"

exit 0
