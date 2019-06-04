#!/bin/bash

set -e

if [ -z $1 -o -z $2 ] ; then
  echo "usage1: smoke_test_docker_image.sh TYPE[pg|influx] IMAGE_TAG"
  exit 1
fi

if [ $1 != "pg" -a $1 != "influx" ] ; then
  echo "usage: smoke_test_docker_image.sh TYPE[pg|influx] IMAGE_TAG"
  exit 1
fi

METRICDBTYPE=$1
IMAGE=$2
CONTAINER_NAME="smoke_test_$METRICDBTYPE"
PGHOST=localhost
PGPORT=9433
PGUSER=pgwatch2
PGPASSWORD=pgwatch2admin
PGDATABASE=pgwatch2_metrics
WEBUIPORT=9081
INFLUXPORT=9086

echo "starting smoke test of Postgres image $IMAGE ..."

echo "launching docker container ..."
DOCKER_RUN=$(docker run -d --rm --cpus=2 -p 9081:8080 -p 9001:3000 -p 9433:5432 -p 9086:8086 --name "$CONTAINER_NAME" $IMAGE)
echo "OK. container $CONTAINER_NAME started"


echo "sleeping 30s..."
sleep 30


echo "checking Web UI response ..."
curl -s localhost:9081/dbs >/dev/null
echo "OK"


echo "adding new DB 'smoke1' to monitoring via POST to Web UI /dbs page..."
http -f POST :$WEBUIPORT/dbs md_unique_name=smoke1 md_dbtype=postgres md_hostname=/var/run/postgresql/ md_port=5432 md_dbname=pgwatch2 \
  md_user=pgwatch2 md_password=pgwatch2admin md_password_type=plain-text md_preset_config_name=basic md_is_enabled=true new=New >/dev/null
echo "OK"


echo "sleeping 120s..."
sleep 120


echo "checking if metrics exists for added DB..."
if [ $METRICDBTYPE == "pg" ]; then
    ROWS=$(psql -qXAtc "select count(*) from db_stats where dbname = 'smoke1'")
else
  ROWS=$(curl -sG http://localhost:$INFLUXPORT/query?pretty=true --data-urlencode "db=pgwatch2" \
  --data-urlencode "q=SELECT count(xlog_location_b) FROM wal WHERE dbname='smoke1'" \
  | jq .results[0].series[0].values[0][1])
fi
if [ ! $ROWS -gt 0 ] ; then
  echo "could not get any db_stats rows for the inserted DB 'smoke1'"
  exit 1
fi
echo "$ROWS rows found from db_stats"


echo "image $CONTAINER_NAME looks OK"


echo "shutting down image..."
docker stop "$CONTAINER_NAME"
echo "OK. Done"
