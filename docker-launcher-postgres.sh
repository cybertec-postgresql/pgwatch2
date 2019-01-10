#!/bin/bash

if [ ! -f /pgwatch2/persistent-config/self-signed-ssl.key -o ! -f /pgwatch2/persistent-config/self-signed-ssl.pem ] ; then
    openssl req -x509 -newkey rsa:4096 -keyout /pgwatch2/persistent-config/self-signed-ssl.key -out /pgwatch2/persistent-config/self-signed-ssl.pem -days 3650 -nodes -sha256 -subj '/CN=pw2'
    cp /pgwatch2/persistent-config/self-signed-ssl.pem /etc/ssl/certs/ssl-cert-snakeoil.pem
    cp /pgwatch2/persistent-config/self-signed-ssl.key /etc/ssl/private/ssl-cert-snakeoil.key
    chown postgres /etc/ssl/certs/ssl-cert-snakeoil.pem /etc/ssl/private/ssl-cert-snakeoil.key
    chmod -R 0600 /etc/ssl/certs/ssl-cert-snakeoil.pem /etc/ssl/private/ssl-cert-snakeoil.key
fi

if [ -n "$PW2_GRAFANASSL" ] ; then
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

if [ ! -d /var/lib/postgresql/11 ]; then
  mkdir /var/lib/postgresql/11 && chown -R postgres:postgres /var/lib/postgresql/11
  pg_dropcluster 11 main
  pg_createcluster --locale en_US.UTF-8 11 main
  echo "include = 'pgwatch_postgresql.conf'" >> /etc/postgresql/11/main/postgresql.conf
  cp /pgwatch2/postgresql.conf /etc/postgresql/11/main/pgwatch_postgresql.conf
  cp /pgwatch2/pg_hba.conf /etc/postgresql/11/main/pg_hba.conf
fi

pg_ctlcluster 11 main start -- --wait

su -c "psql -d postgres -f /pgwatch2/bootstrap/change_pw.sql" postgres
su -c "psql -d postgres -f /pgwatch2/bootstrap/create_db_pgwatch.sql postgres" postgres
su -c "psql -d postgres -f /pgwatch2/bootstrap/create_db_grafana.sql postgres" postgres
su -c "psql -d postgres -f /pgwatch2/bootstrap/create_db_metric_store.sql postgres" postgres
su -c "psql -d pgwatch2 -f /pgwatch2/sql/config_store/config_store.sql" postgres
su -c "psql -d pgwatch2 -f /pgwatch2/sql/config_store/metric_definitions.sql" postgres
su -c "psql -d pgwatch2_metrics -f /pgwatch2/sql/metric_store/metric_store_part_time_dbname.sql" postgres
su -c "psql -d pgwatch2_metrics -f /pgwatch2/sql/metric_store/ensure_partition.sql" postgres
su -c "psql -d pgwatch2 -f /pgwatch2/sql/metric_fetching_helpers/cpu_load_plpythonu.sql" postgres
su -c "psql -d pgwatch2 -f /pgwatch2/sql/metric_fetching_helpers/stat_statements_wrapper.sql" postgres
su -c "psql -d pgwatch2 -f /pgwatch2/sql/metric_fetching_helpers/stat_activity_wrapper.sql" postgres
su -c "psql -d pgwatch2 -f /pgwatch2/sql/metric_fetching_helpers/table_bloat_approx.sql" postgres
su -c "psql -d pgwatch2 -f /pgwatch2/sql/metric_fetching_helpers/wal_size.sql" postgres
su -c "psql -d pgwatch2 -f /pgwatch2/sql/metric_fetching_helpers/psutil_cpu.sql" postgres
su -c "psql -d pgwatch2 -f /pgwatch2/sql/metric_fetching_helpers/psutil_mem.sql" postgres
su -c "psql -d pgwatch2 -f /pgwatch2/sql/metric_fetching_helpers/psutil_disk.sql" postgres
su -c "psql -d pgwatch2 -f /pgwatch2/sql/metric_fetching_helpers/psutil_disk_io_total.sql" postgres

if [ -z "$NOTESTDB" ] ; then
  su -c "psql -d pgwatch2 -f /pgwatch2/bootstrap/insert_test_monitored_db.sql" postgres
fi

touch /pgwatch2/persistent-config/db-bootstrap-done-marker

fi

pg_ctlcluster 11 main start -- --wait

exec /usr/bin/supervisord --configuration=/etc/supervisor/supervisord.conf --nodaemon
