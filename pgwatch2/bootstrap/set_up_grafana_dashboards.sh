#! /bin/bash

# Used with the default Docker image to load Grafana datasource (local Influxdb) and default Dashboard

export PGUSER=postgres

while true ; do

  # It will take some time for Postgres to start and Grafana to do schema initialization
  sleep 3

  DB_OK=$(psql -qAt -c "select count(1) from dashboard" pgwatch2_grafana)

  if [[ $DB_OK == "0" ]] ; then
    break
  fi

done

psql -h /var/run/postgresql -f /pgwatch2/bootstrap/grafana_datasource.sql pgwatch2_grafana
psql -h /var/run/postgresql -f /pgwatch2/bootstrap/grafana_default_dashboard.sql pgwatch2_grafana

exit 0
