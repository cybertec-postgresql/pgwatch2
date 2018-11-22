#!/usr/bin/env bash

###
### For building the pgwatch2-webui docker image
###

# currently only checks if SSL is enabled and if so generates new cert on the first run
if [ ! -f /pgwatch2/persistent-config/self-signed-ssl.key -o ! -f /pgwatch2/persistent-config/self-signed-ssl.pem ] ; then
    openssl req -x509 -newkey rsa:4096 -keyout /pgwatch2/persistent-config/self-signed-ssl.key -out /pgwatch2/persistent-config/self-signed-ssl.pem -days 3650 -nodes -sha256 -subj '/CN=pw2'
    chmod 0600 /pgwatch2/persistent-config/self-signed-ssl.*
fi

exec /pgwatch2/webpy/web.py "$@"
