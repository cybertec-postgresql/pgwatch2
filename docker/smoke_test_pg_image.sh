#!/bin/bash

set -e

if [ -z $1 ] ; then
  echo "usage: smoke_test_pg_image.sh IMAGE_TAG"
  exit 1
fi

IMAGE=$1
CONTAINER_NAME=smoke_test_pg
PGHOST=localhost
PGPORT=9433
PGUSER=pgwatch2
PGPASSWORD=pgwatch2admin
PGDATABASE=pgwatch2_metrics

echo "starting smoke test of Postgres image $IMAGE ..."

echo "launching docker container ..."
DOCKER_RUN=$(docker run -d --rm -it --cpus=2 -p 9081:8080 -p 9001:3000 -p 9433:5432 --name "$CONTAINER_NAME" $IMAGE)

echo "sleeping 30s..."
sleep 30

echo "checking Web UI response ..."
curl -s localhost:9081/dbs >/dev/null

# add new DB to monitor
http -f POST :$PGPORT/dbs md_unique_name=smoke1 md_dbtype=postgres md_hostname=localhost md_port=5432 md_dbname=pgwatch2 \
  md_user=pgwatch2 md_password=pgwatch2admin md_password_type=plain-text md_preset_config_name=basic new=New

echo "sleeping 120s..."
sleep 120

# check some metrics exists
ROWS=(psql -qXAtc "select count(*) from db_stats where dbname = 'smoke1'")

if [ ! $ROWS -gt 0 ] ; then
  echo "could not get any db_stats rows for the inserted DB"
  exit 1
fi

echo "image $CONTAINER_NAME looks OK"

echo "shutting down image..."
docker stop "$CONTAINER_NAME"
echo "OK. Done"

