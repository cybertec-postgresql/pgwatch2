#!/bin/bash

## for testing purposes mostly

export PGHOST=localhost
export PGPORT=5432
export PGUSER=postgres
export PGDATABASE=pgwatch2_grafana

DRY_RUN=1
PW2_DASHBOARD_NAMES=`ls -1 postgres/v8/`

if [ "$?" -ne 0 ]; then
  echo "could not list dashboards...are you in the dashboards root dir?"
  exit 1
fi

if [ -n "$1" ]; then
  DRY_RUN=0
  echo "deleting ALL pw2 dashboards!"
  echo "hit ctl+c now if not sure"
  echo "sleeping 5s..."
  sleep 5
else
  echo "--dry-run on ALL pw2 dashboards. add any parameter to script call to really delete"
fi

for slug in $PW2_DASHBOARD_NAMES ; do
  if [ "$DRY_RUN" -eq 0 ]; then
    SQL="delete from dashboard where slug = '$slug'"
    echo "$SQL"
    echo "$SQL" | psql -Xq
  else
    echo "would delete '$slug' ..."
  fi
done

echo "done"
