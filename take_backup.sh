#!/usr/bin/env bash

# NB! Starting from pgwatch2 version 1.3.0 most users should use Docker volumes defined for single components for easier updating
# Also note that after below update steps on rare occasions (when getting according schema errors from pgwatch2 daemon)
# some migration scripts from the "pgwatch2/sql/datastore_setup/migrations" might still be needed to roll out manually
# on the Postgres config DB.

NAME=$1
BACKUP_FOLDER=pgwatch2_backup_$NAME

# change these as needed!
PGHOST=127.0.0.1
PGPORT=5432
PGUSER=pgwatch2
PGPASSWORD=pgwatch2admin
PGWATCHDATABASE=pgwatch2
GRAFANADATABASE=pgwatch2_grafana
INFLUXHOST=0.0.0.0
INFLUXPORT=8088

if [ -z $1 ] ; then
    echo "usage: ./take_backup.sh NAME"
    exit 1
fi


mkdir  $BACKUP_FOLDER
cd $BACKUP_FOLDER
echo "starting pgwatch2 backup named $NAME into folder $BACKUP_FOLDER"

if [ -d $BACKUP_FOLDER/$NAME ] ; then
    echo "backup with name $NAME already exists!"
    exit 1
fi


echo "backing up Postgres config store DB..."
pg_dump -h $PGHOST -p $PGPORT -U $PGUSER -n pgwatch2 $PGWATCHDATABASE > pgwatch2_config.sql


echo "backing up Grafana config DB..."
pg_dump -h $PGHOST -p $PGPORT -U $PGUSER -n public $GRAFANADATABASE > grafana_config.sql


echo "backing up InfluxDB pgwatch2 DB into folder influxdb_backup_$NAME..."
# NB! you need to have same version locally or log into the docker image, remote version can be determined e.g. with:
# influx -host $INFLUXHOST -port $INFLUXPORT -execute "show DIAGNOSTICS" | grep -Eo '^master\s+[a-z0-9]+\s+[0-9\.]+$' | grep -Eo '[0-9\.]+$'
influxd backup -database pgwatch2 -host ${INFLUXHOST}:${INFLUXPORT} influxdb_backup

echo "done!"



############
# STEPS FOR RESTORING DATA FROM A OLDER DOCKER VERSION
#
# FYI - restoring cannot be currently fully automated so here just the steps
############

# 1. make sure you have successful backups from old Docker container for all components from above
# 2. stop the old container
# 3. launch the new docker container with specifying a shared volume to access the backup easily (you could also set up ssh etc)
#       docker run ... -v ~/pgwatch2_backups:/pgwatch2_backups:rw,z ...
#       nb! when having problems accessing the share with SELinux see Github issue #22 for potential relief.
# 4. connect to the Postgres DB and rename "pgwatch2" and "pgwatch2_grafana" databases to "*_original" for example and
# recreate them (could also just drop and recreate, but just in case...)
# 5. restore both Postgres DB dumps
#       psql -f ~/pgwatch2_backups/pgwatch2_backup_20170123/pgwatch2_config.sql pgwatch2
#       psql -f ~/pgwatch2_backups/pgwatch2_backup_20170123/grafana_config.sql pgwatch2_grafana
# 6. Restore InfluxDB metrics data. Depending on InfluxDB version there are 2 paths: offline for 1.5 and lesser or oline
# for 1.5+
#
# Offline steps for pre v1.5:
#
#  * log into the running Docker image and kill the InfluxDB process (as restoring requires it)
#       pkill influxd
#  * restore InfluxDB meta files
#       influxd restore -metadir /var/lib/influxdb/meta /pgwatch2_backups/influxdb_backup
#  * restore InfluxDB data files (real metric infos)
#       influxd restore -database pgwatch2 -datadir /var/lib/influxdb/data /pgwatch2_backups/influxdb_backup
#
# Online steps for v1.5+:
#
#  * drop the exising empty pgwatch2 DB if any
#  * do the online restore
#       influxd restore -db pgwatch2 -online $BACKUP_FOLDER/influxdb_backup/
#
# 7. restart the Docker image and check that old config and metrics are there
#        docker stop pw2 && docker start pw2
# 8. done!
