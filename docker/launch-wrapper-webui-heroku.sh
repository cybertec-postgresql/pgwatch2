#!/usr/bin/env bash

echo "pgwatch2 webui starting ..."

###
### For building the pgwatch2-webui docker image
###

# currently only checks if SSL is enabled and if so generates new cert on the first run
if [ ! -f /pgwatch2/persistent-config/self-signed-ssl.key -o ! -f /pgwatch2/persistent-config/self-signed-ssl.pem ] ; then
    openssl req -x509 -newkey rsa:4096 -keyout /pgwatch2/persistent-config/self-signed-ssl.key -out /pgwatch2/persistent-config/self-signed-ssl.pem -days 3650 -nodes -sha256 -subj '/CN=pw2'
    chmod 0600 /pgwatch2/persistent-config/self-signed-ssl.*
fi

#This regular expression is used to parse and extract information from a PostgreSQL database connection string in the format "postgres://username:password@host:port/database".
#
# - "^postgres://" is the starting point of the string, indicating that it begins with the protocol "postgres://".
# - "([^:]+)" captures any characters that are not a colon ":" one or more times, representing the username in the database connection string.
# - "([^@]+)" captures any characters that are not an "@" symbol one or more times, representing the password in the database connection string.
# - "@([^:]+)" captures any characters that are not a colon ":" after the "@" symbol, representing the host or server address in the database connection string.
# - "([^/]+)" captures any characters that are not a forward slash "/" one or more times, representing the port number in the database connection string.
# - "/(.*)" captures any characters after the forward slash "/", representing the database name in the connection string.

regex="^postgres://([^:]+):([^@]+)@([^:]+):([^/]+)/(.*)$"
if [[ $PGWATCH2_URL =~ $regex ]]; then

export PW2_WEBPORT=${PORT}

export PW2_DATASTORE="postgres"
export PW2_PGUSER=${BASH_REMATCH[1]}
export PW2_PGPASSWORD=${BASH_REMATCH[2]}
export PW2_PGHOST=${BASH_REMATCH[3]}
export PW2_PGPORT=${BASH_REMATCH[4]}
export PW2_PGDATABASE=${BASH_REMATCH[5]}
export PW2_PGSSL="true"

export PW2_PG_METRIC_STORE_CONN_STR=$(echo ${PGWATCH2_URL} | sed 's/postgres:\/\//postgresql:\/\//')?sslmode=require

#export PW2_VERBOSE=vv

exec /pgwatch2/webpy/web.py "$@"

else
echo "PGWATCH2_URL config var is not defined, exiting..."

fi

