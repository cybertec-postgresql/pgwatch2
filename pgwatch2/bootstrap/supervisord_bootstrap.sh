#!/bin/bash

for prog in postgres grafana grafana_dashboard_setup influxdb pgwatch2 webpy ; do
  echo "supervisorctl start $prog ..."
  supervisorctl start $prog
  echo "sleep 5"
  sleep 5
done
