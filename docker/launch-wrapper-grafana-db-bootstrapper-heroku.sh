#!/usr/bin/env bash
# the following is required to use alias psql within the script
shopt -s expand_aliases

# set -e

echo "grafana-db-boostrapper starting ..."

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
### Rolls out grafana db configuration
###

SQL_CMDS=$(cat <<-EOF
ALTER DEFAULT PRIVILEGES FOR ROLE pgwatch2 IN SCHEMA public GRANT SELECT ON TABLES TO pgwatch2_grafana;
ALTER DEFAULT PRIVILEGES FOR ROLE pgwatch2 IN SCHEMA subpartitions GRANT SELECT ON TABLES TO pgwatch2_grafana;

GRANT USAGE ON SCHEMA public TO pgwatch2_grafana;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO pgwatch2_grafana;

GRANT USAGE ON SCHEMA admin TO pgwatch2_grafana;
GRANT SELECT ON ALL TABLES IN SCHEMA admin TO pgwatch2_grafana;

GRANT USAGE ON SCHEMA subpartitions TO pgwatch2_grafana;
GRANT SELECT ON ALL TABLES IN SCHEMA subpartitions TO pgwatch2_grafana;

GRANT CREATE ON SCHEMA public TO pgwatch2_grafana;

EOF
)
echo "$SQL_CMDS" | psql -f-

echo "grafana-db-boostrapper finished"

exit 0
