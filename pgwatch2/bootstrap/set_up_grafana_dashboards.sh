#! /bin/bash

# Used with the default Docker image to load Grafana datasource (local Influxdb) and default Dashboard

export PGUSER=postgres

while true ; do

  # It will take some time for Postgres to start and Grafana to do schema initialization
  sleep 3

  DB_OK=$(psql -qXAt -c "select count(1) from dashboard" pgwatch2_grafana)

  if [[ $? -ne 0 ]] ; then
    continue
  elif [[ $DB_OK -gt 0 ]] ; then
    exit 0
  elif [[ $DB_OK == 0 ]] ; then
    sleep 5 # give Grafana some more time to bootstrap the schema if maybe on some weak cloud instance
    break
  fi

done

GRAFANA_MAJOR_VER=$(grafana-server -v | egrep -o [0-9]{1} | head -1)

psql -h /var/run/postgresql -f /pgwatch2/bootstrap/grafana_datasource.sql pgwatch2_grafana

for slug in $(ls --hide='*.md' /pgwatch2/grafana_dashboards/influxdb/v${GRAFANA_MAJOR_VER}) ; do

echo "inserting dashboard: $slug"
TITLE=$(cat /pgwatch2/grafana_dashboards/influxdb/v${GRAFANA_MAJOR_VER}/${slug}/title.txt)
JSON=$(cat /pgwatch2/grafana_dashboards/influxdb/v${GRAFANA_MAJOR_VER}/${slug}/dashboard.json)

# in Grafana 5 "uid" column was introduced that is normally filled by the app
if [ "$GRAFANA_MAJOR_VER" -gt 4 ] ; then

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

echo "$SQL" | psql -h /var/run/postgresql pgwatch2_grafana

done

psql -h /var/run/postgresql -d pgwatch2_grafana -c "insert into public.dashboard_tag(dashboard_id, term) select id, 'pgwatch2' from public.dashboard on conflict do nothing"

HEALTHCHECK_STAR="INSERT INTO star (user_id, dashboard_id) SELECT 1, id FROM dashboard WHERE slug = 'health-check'"
psql -h /var/run/postgresql -c "$HEALTHCHECK_STAR" pgwatch2_grafana
HOME_DASH="INSERT INTO preferences (org_id, user_id, version, home_dashboard_id, timezone, theme, created, updated, team_id) SELECT 1, 0, 0, id, '', '', now(), now(), 0 FROM dashboard WHERE slug = 'health-check'"
psql -h /var/run/postgresql -c "$HOME_DASH" pgwatch2_grafana

exit 0
