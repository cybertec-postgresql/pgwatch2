#!/bin/bash

## Pushes disk SMART status code to the metrics DB (to enable alerting in Grafana)
## Meant for Cron for example

export PGHOST=localhost
export PGDATABASE=pgwatch2_metrics
export PGUSER=pgwatch2
# for password .pgpass is recommended
export PGPORT=5432

SMART_CMD=$(sudo smartctl --quietmode=silent --health /dev/sda)
RETCODE=$?

METRIC_NAME=smart_health
DBNAME=x
SQL=$(cat <<EOF
insert into ${METRIC_NAME} (time, dbname, data, tag_data)
select now(), '${DBNAME}', '{"smartctl_retcode": ${RETCODE}}', null;
EOF
)
echo $SQL

## check which 'metrics schema' is used from the metrics DB!
#psql -XAtqc "select admin.admin.ensure_partition_metric('${METRIC_NAME}')" &>/dev/null
#psql -XAtqc "select admin.ensure_partition_metric_dbname_time('${METRIC_NAME}', '${DBNAME}', now())" &>/dev/null
psql -XAtqc "select admin.ensure_partition_metric_time('${METRIC_NAME}', now())" &>/dev/null
psql -XAtqc "${SQL}"
