#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""This script doubles the existing PG metrics data with each call, using
intervals found found for each metrics.
NB! Doubling could meana a lot of data so start conservatively
"""

import psycopg2
import psycopg2.extras
import logging
import time

## ADJUST AS NEEDED ##
METRICSCONN_STR = "host=localhost port=5432 dbname=pgwatch2_metrics user=pgwatch2"
HOW_MANY_TIME_TO_DOUBLE = 1   # i.e. when having 1d of data, 5 means there will be 1m (1*2*2*2*2*2)
LOGLVL = logging.INFO   # logging.DEBUG

SQL_TO_DOUBLE_DATA = """
with q_interval as (    -- determine interval from 2 sequential rows
	select * from (
		select time - lag(time) over (order by time) as metric_interval
		from public.{metric}
		where dbname = (select dbname from admin.all_distinct_dbname_metrics dd
                        where exists (select * from public.{metric} where dbname = dd.dbname) limit 1)
        order by time
        limit 2
	) x
	where metric_interval is not null
	limit 1
),
q_min_max_time as (
	select max(time) - min(time) as time_diff from public.{metric}
)
insert into public.{metric}
select time+time_diff+metric_interval, dbname, data, tag_data
from
	public.{metric},
	q_min_max_time,
	q_interval
order by 1, 2;
"""
SQL_SCHEMA_TYPE = "select schema_type from admin.storage_schema_type"
SQL_CREATE_PARTITIONS_METRIC_TIME = """
with q_timespan as (
    select
        max(time)::date+1 as start_time,
        (max(time) + (max(time) - min(time)) + '1d'::interval)::date as end_time
    from
        public.{metric}
)
select
    admin.ensure_partition_metric_time('{metric}', gs)
from 
    q_timespan, generate_series(start_time, end_time, '1d'::interval) gs
"""
SQL_CREATE_PARTITIONS_METRIC_DBNAME_TIME = """
with q_timespan as (
    select
        max(time)::date+1 as start_time,
        (max(time) + (max(time) - min(time)) + '1d'::interval)::date as end_time
    from
        public.{metric}
),
q_distinct_dbnames as (
    select distinct dbname from admin.all_distinct_dbname_metrics
)
select
    admin.ensure_partition_metric_dbname_time('{metric}', dbname, gs)
from 
    q_timespan, q_distinct_dbnames, generate_series(start_time, end_time, '1d'::interval) gs
"""
SQL_GET_TOP_LEVEL_metricS = "select table_name from admin.get_top_level_metric_tables()"
SLEEP_SECONDS_BETWEEN_ROUNDS = 5


def execute(sql, params=None, statement_timeout=None):
    result = []
    
    conn = psycopg2.connect(METRICSCONN_STR)
    conn.autocommit = True
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

    if statement_timeout:
        cur.execute('SET statement_timeout TO %s', (statement_timeout,))

    cur.execute(sql, params)

    if cur.statusmessage.startswith('SELECT') or cur.description:
        result = cur.fetchall()
    else:
        result = [{'rows_affected': str(cur.rowcount)}]
    
    if conn:
        conn.close()
    return result


if __name__ == '__main__':
    logging.basicConfig(format='%(asctime)s %(message)s', level=LOGLVL)

    logging.info("testing connection...")
    execute("select 1")
    logging.info("connection OK...")

    logging.info("determining schema type...")
    ret = execute(SQL_SCHEMA_TYPE)
    schema_type = ret[0]['schema_type']
    if schema_type not in  ['metric', 'metric-time', 'metric-dbname-time']:
        raise Exception('Unexcpected schema type:' + schema_type)
    logging.info("schema type: %s", schema_type)

    logging.info("determining top level tables / metrics...")
    ret = execute(SQL_GET_TOP_LEVEL_metricS)
    all_metrics = [x['table_name'].replace('public.', '') for x in ret]
    logging.info("found %s top level tables: %s", len(all_metrics), all_metrics)

    for i in range(0, HOW_MANY_TIME_TO_DOUBLE):
        logging.info("starting LOOP %s...", i)
                
        for metric in all_metrics:
            
            if schema_type == "metric-time":
                logging.debug("ensuring sub-partitions for next time range...")
                execute(SQL_CREATE_PARTITIONS_METRIC_TIME.format(metric=metric))
                logging.debug("done")
            elif schema_type == "metric-dbname-time":
                logging.debug("ensuring sub-partitions for time range...")
                execute(SQL_CREATE_PARTITIONS_METRIC_DBNAME_TIME.format(metric=metric))
                logging.debug("done")
            
            logging.info("duplicating data for %s...", metric)
            ret = execute(SQL_TO_DOUBLE_DATA.format(metric=metric), statement_timeout=0)
            logging.info("done. rows added: %s", ret[0]['rows_affected'])
        
        logging.info("finished LOOP 1, sleeping %ss...", SLEEP_SECONDS_BETWEEN_ROUNDS)
        time.sleep(SLEEP_SECONDS_BETWEEN_ROUNDS)

    logging.info("script finished!")