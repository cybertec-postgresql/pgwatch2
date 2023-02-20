#!/bin/bash

mkdir -p /var/run/grafana && chown grafana /var/run/grafana
chown grafana:grafana /var/lib/grafana

if [ ! -f /pgwatch2/persistent-config/self-signed-ssl.key -o ! -f /pgwatch2/persistent-config/self-signed-ssl.pem ] ; then
    openssl req -x509 -newkey rsa:4096 -keyout /pgwatch2/persistent-config/self-signed-ssl.key -out /pgwatch2/persistent-config/self-signed-ssl.pem -days 3650 -nodes -sha256 -subj '/CN=pw2'
    cp /pgwatch2/persistent-config/self-signed-ssl.pem /etc/ssl/certs/ssl-cert-snakeoil.pem
    cp /pgwatch2/persistent-config/self-signed-ssl.key /etc/ssl/private/ssl-cert-snakeoil.key
    chown postgres /etc/ssl/certs/ssl-cert-snakeoil.pem /etc/ssl/private/ssl-cert-snakeoil.key
    chmod -R 0600 /etc/ssl/certs/ssl-cert-snakeoil.pem /etc/ssl/private/ssl-cert-snakeoil.key
    chmod -R o+rx /pgwatch2/persistent-config
fi

# enable password encryption by default from v1.8.0
if [ ! -f /pgwatch2/persistent-config/default-password-encryption-key.txt ]; then
  echo -n "${RANDOM}${RANDOM}${RANDOM}${RANDOM}" > /pgwatch2/persistent-config/default-password-encryption-key.txt
  chmod 0600 /pgwatch2/persistent-config/default-password-encryption-key.txt
fi

GRAFANASSL="${PW2_GRAFANASSL,,}"    # to lowercase
if [ "$GRAFANASSL" == "1" ] || [ "${GRAFANASSL:0:1}" == "t" ]; then
    $(grep -q 'protocol = http$' /etc/grafana/grafana.ini)
    if [ "$?" -eq 0 ] ; then
        sed -i 's/protocol = http.*/protocol = https/' /etc/grafana/grafana.ini
    fi
fi

if [ -n "$PW2_GRAFANAUSER" ] ; then
    sed -i "s/admin_user =.*/admin_user = ${PW2_GRAFANAUSER}/" /etc/grafana/grafana.ini
fi

if [ -n "$PW2_GRAFANAPASSWORD" ] ; then
    sed -i "s/admin_password =.*/admin_password = ${PW2_GRAFANAPASSWORD}/" /etc/grafana/grafana.ini
fi

if [ -n "$PW2_GRAFANANOANONYMOUS" ] ; then
CFG=$(cat <<-'HERE'
[auth.anonymous]
enabled = false
HERE
)
echo "$CFG" >> /etc/grafana/grafana.ini
fi

if [ ! -f /pgwatch2/persistent-config/db-bootstrap-done-marker ] ; then

if [ ! -d /var/lib/postgresql/15 ]; then
  mkdir /var/lib/postgresql/15 && chown -R postgres:postgres /var/lib/postgresql/15
  pg_dropcluster 15 main
  pg_createcluster --locale en_US.UTF-8 15 main
  echo "include = 'pgwatch_postgresql.conf'" >> /etc/postgresql/15/main/postgresql.conf
  cp /pgwatch2/postgresql.conf /etc/postgresql/15/main/pgwatch_postgresql.conf
  cp /pgwatch2/pg_hba.conf /etc/postgresql/15/main/pg_hba.conf
fi

pg_ctlcluster 15 main start -- --wait

su -c "psql -d postgres -f /pgwatch2/bootstrap/change_pw.sql" postgres
su -c "psql -d postgres -f /pgwatch2/bootstrap/grant_monitor_to_pgwatch2.sql" postgres
su -c "psql -d postgres -f /pgwatch2/bootstrap/create_db_pgwatch.sql" postgres
su -c "psql -d pgwatch2 -f /pgwatch2/bootstrap/revoke_public_create.sql" postgres
su -c "psql -d postgres -f /pgwatch2/bootstrap/create_db_grafana.sql" postgres
su -c "psql -d postgres -f /pgwatch2/bootstrap/create_db_metric_store.sql" postgres
su -c "psql -d pgwatch2 -f /pgwatch2/sql/config_store/config_store.sql" postgres
su -c "psql -d pgwatch2 -f /pgwatch2/sql/config_store/metric_definitions.sql" postgres
su -c "psql -d pgwatch2_metrics -f /pgwatch2/sql/metric_store/00_schema_base.sql" postgres
su -c "psql -d pgwatch2_metrics -f /pgwatch2/sql/metric_store/01_old_metrics_cleanup_procedure.sql" postgres
if [ "$PW2_PG_SCHEMA_TYPE" == "metric-dbname-time" ] ; then
  su -c "psql -d pgwatch2_metrics -f /pgwatch2/sql/metric_store/metric-dbname-time/metric_store_part_dbname_time.sql" postgres
  su -c "psql -d pgwatch2_metrics -f /pgwatch2/sql/metric_store/metric-dbname-time/ensure_partition_metric_dbname_time.sql" postgres
else
  su -c "psql -d pgwatch2_metrics -f /pgwatch2/sql/metric_store/metric-time/metric_store_part_time.sql" postgres
  su -c "psql -d pgwatch2_metrics -f /pgwatch2/sql/metric_store/metric-time/ensure_partition_metric_time.sql" postgres
fi
su -c "psql -d pgwatch2 -f /pgwatch2/metrics/00_helpers/get_load_average/9.1/metric.sql" postgres
su -c "psql -d pgwatch2 -f /pgwatch2/metrics/00_helpers/get_stat_statements/9.4/metric.sql" postgres
su -c "psql -d pgwatch2 -f /pgwatch2/metrics/00_helpers/get_stat_activity/9.2/metric.sql" postgres
su -c "psql -d pgwatch2 -f /pgwatch2/metrics/00_helpers/get_stat_replication/9.2/metric.sql" postgres
su -c "psql -d pgwatch2 -f /pgwatch2/metrics/00_helpers/get_table_bloat_approx/9.5/metric.sql" postgres
su -c "psql -d pgwatch2 -f /pgwatch2/metrics/00_helpers/get_table_bloat_approx_sql/12/metric.sql" postgres
su -c "psql -d pgwatch2 -f /pgwatch2/metrics/00_helpers/get_wal_size/10/metric.sql" postgres
su -c "psql -d pgwatch2 -f /pgwatch2/metrics/00_helpers/get_psutil_cpu/9.1/metric.sql" postgres
su -c "psql -d pgwatch2 -f /pgwatch2/metrics/00_helpers/get_psutil_mem/9.1/metric.sql" postgres
su -c "psql -d pgwatch2 -f /pgwatch2/metrics/00_helpers/get_psutil_disk/9.1/metric.sql" postgres
su -c "psql -d pgwatch2 -f /pgwatch2/metrics/00_helpers/get_psutil_disk_io_total/9.1/metric.sql" postgres
su -c "psql -d pgwatch2 -c 'create extension pg_qualstats'" postgres

if [ -n "$PW2_TESTDB" ] ; then
  su -c "psql -d pgwatch2 -f /pgwatch2/bootstrap/insert_test_monitored_db.sql" postgres
fi

touch /pgwatch2/persistent-config/db-bootstrap-done-marker

pg_ctlcluster 15 main stop -- --wait

fi

sleep 1

exec /usr/local/bin/supervisord --configuration=/etc/supervisor/supervisord.conf --nodaemon
