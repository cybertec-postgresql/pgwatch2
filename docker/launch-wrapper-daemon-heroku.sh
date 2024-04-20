#!/usr/bin/env bash
# the following is required to use alias psql within the script
shopt -s expand_aliases
alias psqla="psql ${DATABASE_URL} -v ON_ERROR_STOP=1"

echo "pgwatch2 collector starting ..."

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

export PW2_DATASTORE="postgres"
export PW2_PGUSER=${BASH_REMATCH[1]}
export PW2_PGPASSWORD=${BASH_REMATCH[2]}
export PW2_PGHOST=${BASH_REMATCH[3]}
export PW2_PGPORT=${BASH_REMATCH[4]}
export PW2_PGDATABASE=${BASH_REMATCH[5]}
export PW2_PGSSL="true"

#export PW2_PG_METRIC_STORE_CONN_STR=$(echo ${PGWATCH2_URL} | sed 's/postgres:\/\//postgresql:\/\//')?sslmode=require
export PW2_PG_METRIC_STORE_CONN_STR=${PGWATCH2_URL}?sslmode=require


# PW2_VERBOSE: vv


# loop through all the PGWATCH2_MONITOREDDB_ attached credentials of the monitored DBs and upsert their configuration records
# it allows to automatically insert/update those records even when credentials are updated

echo "looking for PGWATCH2_MONITOREDDB_ attached credentials to be added automatically ..."

for monitoreddb_env_var in $(env | grep ^PGWATCH2_MONITOREDDB_); do
    MDB_VAR_NAME=$(echo $monitoreddb_env_var | cut -d= -f1)
    MDB_VAR_VALUE=$(echo $monitoreddb_env_var | cut -d= -f2)   

if [[ $MDB_VAR_VALUE =~ $regex ]]; then
    MONITOREDDB_PGUSER=${BASH_REMATCH[1]}
    MONITOREDDB_PGPASSWORD=${BASH_REMATCH[2]}
    MONITOREDDB_PGHOST=${BASH_REMATCH[3]}
    MONITOREDDB_PGPORT=${BASH_REMATCH[4]}
    MONITOREDDB_PGDATABASE=${BASH_REMATCH[5]}

    echo "upserting $MDB_VAR_NAME into pgwatch2.monitored_db ..."

    SQL_INS=$(cat <<-EOF
INSERT INTO pgwatch2.monitored_db (md_unique_name, md_preset_config_name, md_hostname, md_port, md_dbname, md_user, md_password, md_password_type, md_sslmode)
  select '$MDB_VAR_NAME', 'heroku_postgres', '$MONITOREDDB_PGHOST', '$MONITOREDDB_PGPORT', '$MONITOREDDB_PGDATABASE', '$MONITOREDDB_PGUSER', '$MONITOREDDB_PGPASSWORD', 'aes-gcm-256', 'require'
  ON CONFLICT (md_unique_name) DO UPDATE SET md_hostname = '$MONITOREDDB_PGHOST', md_port = '$MONITOREDDB_PGPORT', md_dbname = '$MONITOREDDB_PGDATABASE', md_user = '$MONITOREDDB_PGUSER', md_password = '$MONITOREDDB_PGPASSWORD' 
  WHERE pgwatch2.monitored_db.md_unique_name = '$MDB_VAR_NAME' AND pgwatch2.monitored_db.md_hostname != '$MONITOREDDB_PGHOST' OR pgwatch2.monitored_db.md_port != '$MONITOREDDB_PGPORT' OR pgwatch2.monitored_db.md_dbname != '$MONITOREDDB_PGDATABASE' OR pgwatch2.monitored_db.md_user != '$MONITOREDDB_PGUSER' OR pgwatch2.monitored_db.md_password != '$MONITOREDDB_PGPASSWORD' ;
EOF
)
    echo "$SQL_INS" | psqla -f-
fi
done


/pgwatch2/pgwatch2

else
echo "PGWATCH2_URL config var is not defined, exiting..."

fi
