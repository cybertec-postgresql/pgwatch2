#!/bin/bash



## Ensure getpwuid and friends work with OpenShift

$(grep -q pgwatch2 /etc/passwd)
if [ "$?" -ne 0 ] ; then
    echo pgwatch2:x:$(id -u):$(id -g):pgwatch2:/home/postgres/:/bin/bash >> /etc/passwd
fi

if [ ! -f /pgwatch2/persistent-config/self-signed-ssl.key -o ! -f /pgwatch2/persistent-config/self-signed-ssl.pem ] ; then
    openssl req -x509 -newkey rsa:4096 -keyout /pgwatch2/persistent-config/self-signed-ssl.key -out /pgwatch2/persistent-config/self-signed-ssl.pem -days 3650 -nodes -sha256 -subj '/CN=pw2'
    chmod 0600 /pgwatch2/persistent-config/self-signed-ssl.*
fi

if [ -n "$PW2_GRAFANASSL" ] ; then
    $(grep -q 'protocol = http$' /etc/grafana/grafana.ini)
    if [ "$?" -eq 0 ] ; then
        sed -i 's/protocol = http.*/protocol = https/' /etc/grafana/grafana.ini
    fi
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

echo "ssl_key_file='/pgwatch2/persistent-config/self-signed-ssl.key'" >> /etc/postgresql/9.5/main/pgwatch_postgresql.conf
echo "ssl_cert_file='/pgwatch2/persistent-config/self-signed-ssl.pem'" >> /etc/postgresql/9.5/main/pgwatch_postgresql.conf

if [ ! -f /pgwatch2/persistent-config/db-bootstrap-done-marker ] ; then

# need to init here as Postgres requires chmod 0700 for datadir
if [ ! -d /var/lib/postgresql/9.5 ]; then
  mkdir /var/lib/postgresql/9.5
fi
/usr/lib/postgresql/9.5/bin/initdb -D /var/lib/postgresql/9.5/main/ --locale en_US.UTF-8 -E UTF8 -U postgres

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


touch /pgwatch2/persistent-config/db-bootstrap-done-marker

fi

/usr/lib/postgresql/9.5/bin/pg_ctl -D /var/lib/postgresql/9.5/main/ -o "-c config_file=/etc/postgresql/9.5/main/postgresql.conf" -w start


exec /usr/bin/supervisord --configuration=/etc/supervisor/supervisord.conf --nodaemon
