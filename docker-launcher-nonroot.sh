#!/bin/bash


if [ ! -f /pgwatch2/db-bootstrap-done-marker ] ; then

## Ensure getpwuid and friends work with OpenShift
echo pgwatch2:x:$(id -u):$(id -g):pgwatch2:/home/postgres/:/bin/bash >> /etc/passwd

# need to init here as Postgres requires chmod 0700 for datadir
/usr/lib/postgresql/9.5/bin/initdb -D /var/lib/postgresql/9.5/main/ --locale en_US.UTF-8 -E UTF8 -U postgres

echo "ssl_key_file='/pgwatch2/self-signed-ssl.key'" >> /etc/postgresql/9.5/main/pgwatch_postgresql.conf
echo "ssl_cert_file='/pgwatch2/self-signed-ssl.pem'" >> /etc/postgresql/9.5/main/pgwatch_postgresql.conf

if [ ! -f /pgwatch2/ssl_key.pem -o ! -f /pgwatch2/ssl_cert.pem ] ; then
    openssl req -x509 -newkey rsa:4096 -keyout /pgwatch2/self-signed-ssl.key -out /pgwatch2/self-signed-ssl.pem -days 3650 -nodes -sha256 -subj '/CN=pw2'
    chmod 0600 /pgwatch2/self-signed-ssl.*
fi

if [ -n "$PW2_GRAFANASSL" ] ; then
    $(grep -q 'protocol = http$' /etc/grafana/grafana.ini)
    if [ "$?" -eq 0 ] ; then
        sed -i 's/protocol = http.*/protocol = https/' /etc/grafana/grafana.ini
    fi
fi

/usr/lib/postgresql/9.5/bin/postgres --single -j -D /var/lib/postgresql/9.5/main -c config_file=/etc/postgresql/9.5/main/postgresql.conf postgres </pgwatch2/bootstrap/change_pw.sql
/usr/lib/postgresql/9.5/bin/postgres --single -j -D /var/lib/postgresql/9.5/main -c config_file=/etc/postgresql/9.5/main/postgresql.conf postgres </pgwatch2/bootstrap/create_db_pgwatch.sql
/usr/lib/postgresql/9.5/bin/postgres --single -j -D /var/lib/postgresql/9.5/main -c config_file=/etc/postgresql/9.5/main/postgresql.conf postgres </pgwatch2/bootstrap/create_db_grafana.sql
/usr/lib/postgresql/9.5/bin/postgres --single -j -D /var/lib/postgresql/9.5/main -c config_file=/etc/postgresql/9.5/main/postgresql.conf pgwatch2 </pgwatch2/sql/datastore_setup/config_store.sql
/usr/lib/postgresql/9.5/bin/postgres --single -j -D /var/lib/postgresql/9.5/main -c config_file=/etc/postgresql/9.5/main/postgresql.conf pgwatch2 </pgwatch2/sql/datastore_setup/metric_definitions.sql
/usr/lib/postgresql/9.5/bin/postgres --single -j -D /var/lib/postgresql/9.5/main -c config_file=/etc/postgresql/9.5/main/postgresql.conf pgwatch2 </pgwatch2/sql/metric_fetching_helpers/cpu_load_plpythonu.sql
/usr/lib/postgresql/9.5/bin/postgres --single -j -D /var/lib/postgresql/9.5/main -c config_file=/etc/postgresql/9.5/main/postgresql.conf pgwatch2 </pgwatch2/sql/metric_fetching_helpers/stat_statements_wrapper.sql
/usr/lib/postgresql/9.5/bin/postgres --single -j -D /var/lib/postgresql/9.5/main -c config_file=/etc/postgresql/9.5/main/postgresql.conf pgwatch2 </pgwatch2/sql/metric_fetching_helpers/stat_activity_wrapper.sql
/usr/lib/postgresql/9.5/bin/postgres --single -j -D /var/lib/postgresql/9.5/main -c config_file=/etc/postgresql/9.5/main/postgresql.conf pgwatch2 </pgwatch2/sql/metric_fetching_helpers/table_bloat_approx.sql

if [ -z "$NOTESTDB" ] ; then
/usr/lib/postgresql/9.5/bin/postgres --single -j -D /var/lib/postgresql/9.5/main -c config_file=/etc/postgresql/9.5/main/postgresql.conf pgwatch2 </pgwatch2/bootstrap/insert_test_monitored_db.sql
fi


touch /pgwatch2/db-bootstrap-done-marker

fi

/usr/lib/postgresql/9.5/bin/pg_ctl -D /var/lib/postgresql/9.5/main/ -o "-c config_file=/etc/postgresql/9.5/main/postgresql.conf" -w start


exec /usr/bin/supervisord --configuration=/etc/supervisor/supervisord.conf --nodaemon
