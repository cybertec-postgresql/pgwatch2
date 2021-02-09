#!/bin/bash

mkdir /var/run/grafana && chown grafana /var/run/grafana

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

if [ ! -d /var/lib/postgresql/9.5 ]; then
  mkdir /var/lib/postgresql/9.5 && chown -R postgres:postgres /var/lib/postgresql/9.5
  pg_dropcluster 9.5 main
  pg_createcluster --locale en_US.UTF-8 9.5 main
  echo "include = 'pgwatch_postgresql.conf'" >> /etc/postgresql/9.5/main/postgresql.conf
  cp /pgwatch2/postgresql.conf /etc/postgresql/9.5/main/pgwatch_postgresql.conf
  cp /pgwatch2/pg_hba.conf /etc/postgresql/9.5/main/pg_hba.conf
fi

su -c "/usr/lib/postgresql/9.5/bin/postgres --single -j -D /var/lib/postgresql/9.5/main -c config_file=/etc/postgresql/9.5/main/postgresql.conf postgres </pgwatch2/bootstrap/change_pw.sql" postgres
su -c "/usr/lib/postgresql/9.5/bin/postgres --single -j -D /var/lib/postgresql/9.5/main -c config_file=/etc/postgresql/9.5/main/postgresql.conf postgres </pgwatch2/bootstrap/create_db_pgwatch.sql" postgres
su -c "/usr/lib/postgresql/9.5/bin/postgres --single -j -D /var/lib/postgresql/9.5/main -c config_file=/etc/postgresql/9.5/main/postgresql.conf pgwatch2 </pgwatch2/bootstrap/revoke_public_create.sql" postgres
su -c "/usr/lib/postgresql/9.5/bin/postgres --single -j -D /var/lib/postgresql/9.5/main -c config_file=/etc/postgresql/9.5/main/postgresql.conf postgres </pgwatch2/bootstrap/create_db_grafana.sql" postgres
su -c "/usr/lib/postgresql/9.5/bin/postgres --single -j -D /var/lib/postgresql/9.5/main -c config_file=/etc/postgresql/9.5/main/postgresql.conf pgwatch2 </pgwatch2/sql/config_store/config_store.sql" postgres
su -c "/usr/lib/postgresql/9.5/bin/postgres --single -j -D /var/lib/postgresql/9.5/main -c config_file=/etc/postgresql/9.5/main/postgresql.conf pgwatch2 </pgwatch2/sql/config_store/metric_definitions.sql" postgres
su -c "/usr/lib/postgresql/9.5/bin/postgres --single -j -D /var/lib/postgresql/9.5/main -c config_file=/etc/postgresql/9.5/main/postgresql.conf pgwatch2 </pgwatch2/metrics/00_helpers/get_load_average/9.1/metric.sql" postgres
su -c "/usr/lib/postgresql/9.5/bin/postgres --single -j -D /var/lib/postgresql/9.5/main -c config_file=/etc/postgresql/9.5/main/postgresql.conf pgwatch2 </pgwatch2/metrics/00_helpers/get_stat_statements/9.2/metric.sql" postgres
su -c "/usr/lib/postgresql/9.5/bin/postgres --single -j -D /var/lib/postgresql/9.5/main -c config_file=/etc/postgresql/9.5/main/postgresql.conf pgwatch2 </pgwatch2/metrics/00_helpers/get_stat_activity/9.2/metric.sql" postgres
su -c "/usr/lib/postgresql/9.5/bin/postgres --single -j -D /var/lib/postgresql/9.5/main -c config_file=/etc/postgresql/9.5/main/postgresql.conf pgwatch2 </pgwatch2/metrics/00_helpers/get_stat_replication/9.2/metric.sql" postgres
su -c "/usr/lib/postgresql/9.5/bin/postgres --single -j -D /var/lib/postgresql/9.5/main -c config_file=/etc/postgresql/9.5/main/postgresql.conf pgwatch2 </pgwatch2/metrics/00_helpers/get_table_bloat_approx/9.5/metric.sql" postgres
su -c "/usr/lib/postgresql/9.5/bin/postgres --single -j -D /var/lib/postgresql/9.5/main -c config_file=/etc/postgresql/9.5/main/postgresql.conf pgwatch2 </pgwatch2/metrics/00_helpers/get_table_bloat_approx_sql/9.0/metric.sql" postgres
su -c "/usr/lib/postgresql/9.5/bin/postgres --single -j -D /var/lib/postgresql/9.5/main -c config_file=/etc/postgresql/9.5/main/postgresql.conf pgwatch2 </pgwatch2/metrics/00_helpers/get_psutil_cpu/9.1/metric.sql" postgres
su -c "/usr/lib/postgresql/9.5/bin/postgres --single -j -D /var/lib/postgresql/9.5/main -c config_file=/etc/postgresql/9.5/main/postgresql.conf pgwatch2 </pgwatch2/metrics/00_helpers/get_psutil_mem/9.1/metric.sql" postgres
su -c "/usr/lib/postgresql/9.5/bin/postgres --single -j -D /var/lib/postgresql/9.5/main -c config_file=/etc/postgresql/9.5/main/postgresql.conf pgwatch2 </pgwatch2/metrics/00_helpers/get_psutil_disk/9.1/metric.sql" postgres
su -c "/usr/lib/postgresql/9.5/bin/postgres --single -j -D /var/lib/postgresql/9.5/main -c config_file=/etc/postgresql/9.5/main/postgresql.conf pgwatch2 </pgwatch2/metrics/00_helpers/get_psutil_disk_io_total/9.1/metric.sql" postgres

if [ -n "$PW2_TESTDB" ] ; then
  su -c "/usr/lib/postgresql/9.5/bin/postgres --single -j -D /var/lib/postgresql/9.5/main -c config_file=/etc/postgresql/9.5/main/postgresql.conf pgwatch2 </pgwatch2/bootstrap/insert_test_monitored_db_influx.sql" postgres
fi

touch /pgwatch2/persistent-config/db-bootstrap-done-marker

fi

sleep 1

exec /usr/local/bin/supervisord --configuration=/etc/supervisor/supervisord.conf --nodaemon
