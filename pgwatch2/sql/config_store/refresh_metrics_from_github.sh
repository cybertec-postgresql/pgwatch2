#!/bin/bash

# Refreshes SQL metric definitions directly from Github

set -e

export PGHOST=localhost
export PGPORT=5432
export PGUSER=postgres
export PGDATABASE=pgwatch2

GITHUB_METRICS=https://raw.githubusercontent.com/cybertec-postgresql/pgwatch2/master/pgwatch2/sql/config_store/metric_definitions.sql
METRICS_TMP_FILE=/tmp/pgwatch2_latest_metric_defs.sql
METRICS_BACKUP_FILE=/tmp/pgwatch2_old_metric_defs.copy
DRY_RUN=1

DIFF_SQL=$(cat <<-EOF
SELECT COUNT(*) FROM tmp_pgwatch2_metric;
EOF
)

if [ -z "$1" ]; then
  echo "*** running in dry-run mode, add 'yes' parameter to script to confirm change ***"
else
  DRY_RUN=0
fi

echo "getting new metric definitions from Github ..."
wget -q -O $METRICS_TMP_FILE $GITHUB_METRICS
if [[ "$?" -ne 0 ]] ; then
  echo "could not fetch new metrics defs from Github, check the URL / connectivity ..."
  exit 1
fi
echo "OK. stored to $METRICS_TMP_FILE"

if [ "$DRY_RUN" -eq 0 ]; then
  echo "saving a backup of old metric definitions to $METRICS_BACKUP_FILE ..."
  psql -qXAt -c "\copy pgwatch2.metric to '$METRICS_BACKUP_FILE'"
  psql -qX -c "select count(*) as old_total_metric_definition_count from pgwatch2.metric"
  psql -qXAt -c "TRUNCATE pgwatch2.metric"
  echo "inserting new metric definitions from $METRICS_TMP_FILE ..."
  sleep 2
  psql -qXAt -f "$METRICS_TMP_FILE"
  psql -qX -c "select count(*) as new_total_metric_definition_count from pgwatch2.tmp_pgwatch2_metric"
  echo "done"
else
  # create and load new metrics into a temp table, insert new metrics and diff with old ones
  echo "create and load new metrics into a temp table, insert new metrics and diff with old ones"
  echo "CREATE UNLOGGED TABLE IF NOT EXISTS pgwatch2.tmp_pgwatch2_metric AS SELECT * FROM pgwatch2.metric WHERE false;"
  psql -qXAt -c "CREATE UNLOGGED TABLE IF NOT EXISTS pgwatch2.tmp_pgwatch2_metric (LIKE pgwatch2.metric INCLUDING ALL)"
  psql -qXAt -c "TRUNCATE pgwatch2.tmp_pgwatch2_metric"
  echo "CREATE UNLOGGED TABLE IF NOT EXISTS pgwatch2.tmp_pgwatch2_metric_attribute AS SELECT * FROM pgwatch2.metric_attribute WHERE false;"
  psql -qXAt -c "CREATE UNLOGGED TABLE IF NOT EXISTS pgwatch2.tmp_pgwatch2_metric_attribute (LIKE pgwatch2.metric_attribute INCLUDING ALL)"
  psql -qXAt -c "TRUNCATE pgwatch2.tmp_pgwatch2_metric_attribute"
  cat "$METRICS_TMP_FILE" | sed "s/into pgwatch2.metric/into pgwatch2.tmp_pgwatch2_metric/g" | sed "s/= pgwatch2.metric/= pgwatch2.tmp_pgwatch2_metric/g" | psql -qXAt
  echo "*** LIST OF CHANGES ***"
  psql -qX -c "select 'TO BE REMOVED' as action, count(*), array_agg(distinct m_name) as metrics from pgwatch2.metric o where not exists (select * from pgwatch2.tmp_pgwatch2_metric where m_name = o.m_name);"
  psql -qX -c "select 'TO BE ADDED' as action, count(*), array_agg(distinct m_name) as metrics from pgwatch2.tmp_pgwatch2_metric n where not exists (select * from pgwatch2.metric where m_name = n.m_name);"
  psql -qX -c "select 'TO BE CHANGED' as action, count(distinct m_name), array_agg(distinct m_name) as metrics from pgwatch2.tmp_pgwatch2_metric n where exists (select * from pgwatch2.metric where m_name = n.m_name and m_pg_version_from = n.m_pg_version_from and m_master_only = n.m_master_only and (coalesce(m_sql, '') != coalesce(n.m_sql, '') or  coalesce(m_sql_su, '') != coalesce (n.m_sql_su, '')))"
  # psql -qXAt -c "DROP TABLE IF EXISTS pgwatch2.tmp_pgwatch2_metric;"
  # psql -qXAt -c "DROP TABLE IF EXISTS pgwatch2.tmp_pgwatch2_metric_attribute;"
fi
