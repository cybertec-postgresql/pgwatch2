#!/bin/bash

# To import all dashboards using default datasource

export PGHOST=localhost
export PGPORT=5432
export PGUSER=postgres
export PGDATABASE=pgwatch2_grafana

GRAFANA_DB_TYPE=postgres
GRAFANA_MAJOR_VER=8
DASHBOARDS_BASE_PATH="."  # change if executing not from file's original Git location
DASHBOARD_NAME_SUFFIX=  # adjust if no extra info wanted besides the imported dashboard name
# DASHBOARD_NAME_SUFFIX=`date +%Y-%m-%d`

DEFAULT_DATASOURCE_ID=$(psql -qXAt -c "select id from data_source where is_default")
if [[ $? -ne 0 ]] ; then
  echo "could not connect to grafana, check PGHOST and co"
  exit 1
fi

for slug in $(ls --hide='*.md' ${DASHBOARDS_BASE_PATH}/${GRAFANA_DB_TYPE}/v${GRAFANA_MAJOR_VER}) ; do

TITLE="$(cat ${DASHBOARDS_BASE_PATH}/${GRAFANA_DB_TYPE}/v${GRAFANA_MAJOR_VER}/${slug}/title.txt) $DASHBOARD_NAME_SUFFIX"
JSON=$(cat ${DASHBOARDS_BASE_PATH}/${GRAFANA_DB_TYPE}/v${GRAFANA_MAJOR_VER}/${slug}/dashboard.json)
echo "inserting from folder '$slug' as '$TITLE'"

# in Grafana 5 "uid" column was introduced that is normally filled by the app
if [ "$GRAFANA_MAJOR_VER" -gt 4 ] ; then

GUID=$(echo "$JSON" | md5sum | egrep -o "^.{9}")
SQL='insert into dashboard (version, org_id, created, updated, updated_by, created_by, gnet_id, slug, title, data, uid) values (0, 1, now(), now(), 1, 1, 0'
for d in "$slug" "$TITLE" "$JSON" "$slug" ; do
  SQL+=",\$SQL\$${d}\$SQL\$"
done

else

SQL='insert into dashboard (version, org_id, created, updated, updated_by, created_by, gnet_id, slug, title, data) values (0, 1, now(), now(), 1, 1, 0'
for d in "$slug" "$TITLE" "$JSON" ; do
SQL+=",\$SQL\$${d}\$SQL\$"
done

fi

SQL+=")"

echo "$SQL" | psql -Xq

done

echo "done"
