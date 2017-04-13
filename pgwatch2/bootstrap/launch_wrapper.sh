#!/usr/bin/env bash

# currently only checks if SSL is enabled and if so generates new cert on the first run
if [ -n "$PW2_WEBSSL" -o -n "$PW2_GRAFANASSL" ] ; then
    if [ ! -f /pgwatch2/ssl_key.pem -o ! -f /pgwatch2/ssl_cert.pem ] ; then
        openssl req -x509 -newkey rsa:4096 -keyout /pgwatch2/ssl_key.pem -out /pgwatch2/ssl_cert.pem -days 3650 -nodes -sha256 -subj '/CN=pw2'
    fi
fi

if [ -n "$PW2_GRAFANASSL" ] ; then
    sed -i 's/protocol = http.*/protocol = https/' /etc/grafana/grafana.ini
fi

supervisorctl start grafana
supervisorctl start webpy
