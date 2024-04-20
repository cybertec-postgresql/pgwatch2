#!/usr/bin/env bash

echo "pgwatch2 grafana starting ..."

#This regular expression is used to parse and extract information from a PostgreSQL database connection string in the format "postgres://username:password@host:port/database".
#
# - "^postgres://" is the starting point of the string, indicating that it begins with the protocol "postgres://".
# - "([^:]+)" captures any characters that are not a colon ":" one or more times, representing the username in the database connection string.
# - "([^@]+)" captures any characters that are not an "@" symbol one or more times, representing the password in the database connection string.
# - "@([^:]+)" captures any characters that are not a colon ":" after the "@" symbol, representing the host or server address in the database connection string.
# - "([^/]+)" captures any characters that are not a forward slash "/" one or more times, representing the port number in the database connection string.
# - "/(.*)" captures any characters after the forward slash "/", representing the database name in the connection string.

regex="^postgres://([^:]+):([^@]+)@([^:]+):([^/]+)/(.*)$"
if [[ $PGWATCH2_GRAFANA_URL =~ $regex ]]; then

export GF_DATABASE_TYPE="postgres"
export GF_DATABASE_USER=${BASH_REMATCH[1]}
export GF_DATABASE_PASSWORD=${BASH_REMATCH[2]}
export GF_DATABASE_HOST=${BASH_REMATCH[3]}
export GF_DATABASE_PORT=${BASH_REMATCH[4]}
export GF_DATABASE_NAME=${BASH_REMATCH[5]}

export GF_DATABASE_SSL_MODE=require


export GF_SERVER_HTTP_PORT=${PORT}
export GF_SERVER_PROTOCOL=http

/run.sh

else
echo "PGWATCH2_GRAFANA_URL config var is not defined, exiting..."

fi
