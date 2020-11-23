#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import psycopg2
import psycopg2.extras
import os
import sys
import argparse
import logging


PGWATCH2_METRIC_NAME = 'vmstat'
VMSTAT_BYTE_UNITS = {'k': 1000, 'K': 1024, 'm': 1000000, 'M': 1048576}

args = None  # cmd. line input params
timezone = None
linesProcessed = 0
metricsDBConn = None  # re-use conn if inputting a file
vmstatBlockBytes = 1024


def getPGConnection(autocommit=True):
    conn = psycopg2.connect(host=args.host, port=args.port, database=args.dbname, user=args.user, sslmode='prefer')
    if autocommit:
        conn.autocommit = True
    return conn


def executeSQL(sql, params=None, connection=None, statement_timeout=None, quiet=False, async_commit=False):
    def try_close(c):
        if c:
            try:
                c.close()
            except:
                logging.exception('failed to close PG connection')
    result = []
    conn = None
    try:
        if connection:
            conn = connection
        else:
            conn = getPGConnection()

        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        if statement_timeout:
            cur.execute("SET statement_timeout TO '{}'".format(
                statement_timeout))

        if async_commit:
            cur.execute("SET synchronous_commit TO off")

        cur.execute(sql, params)
        if cur.statusmessage.startswith('SELECT') or cur.description:
            result = cur.fetchall()
        else:
            result = [{'rows_affected': str(cur.rowcount)}]
    except Exception as e:
        try_close(conn)
        if quiet:
            logging.exception('failed to execute "{}" on datastore'.format(sql))
            return result, str(e)
        else:
            raise

    if not connection:
        try_close(conn)  # auto-close automatically opened connections
    return result, None


def ensureSubpartition(dbname, time):  # TODO could be optimized
    sqlSchemaType = 'SELECT schema_type FROM admin.storage_schema_type'
    sqlEnsureMetricTime = 'select * from admin.ensure_partition_metric_time(%s, %s)'
    sqlEnsureMetricDbnameTime = 'select * from admin.ensure_partition_metric_dbname_time(%s, %s, %s)'

    ret, err = executeSQL(sqlSchemaType, connection=metricsDBConn)
    if ret and len(ret) == 1:
        if ret[0]['schema_type'] == 'metric-time':
            executeSQL(sqlEnsureMetricTime, (PGWATCH2_METRIC_NAME, time), connection=metricsDBConn)
        elif ret[0]['schema_type'] == 'metric-dbname-time':
            executeSQL(sqlEnsureMetricDbnameTime, (PGWATCH2_METRIC_NAME, dbname, time), connection=metricsDBConn)


def parseVmstatLineToDict(line):
    '''
procs -----------------------memory---------------------- ---swap-- -----io---- -system-- --------cpu-------- -----timestamp-----
 r  b         swpd         free         buff        cache   si   so    bi    bo   in   cs  us  sy  id  wa  st                 EET
 0  0            0      2504348      1898912     18470548    0    0     2    32    8    8   2   1  98   0   0 2020-11-13 00:57:58
 0 1          2           3             4            5       6    7     8     9    10  11  12   13  14  15  16  17         18
    '''
    global linesProcessed
    global timezone

    if not line or line.startswith('procs') or (line.startswith(' r') and timezone):
        return None, None

    ret = {}
    splits = line.split()
    if len(splits) < 7:
        return None, None

    if not timezone and splits[0] == 'r':
        timezone = splits[-1]
        return None, None
    if len(splits) != 19:
        logging.fatal('unexpected input line. splits: %s', splits)

    linesProcessed += 1
    if linesProcessed == 0:
        return None, None   # skip the 'averages since boot' line

    time = splits[17] + ' ' + splits[18] + ' ' + timezone
    ret['r'] = int(splits[0])
    ret['b'] = int(splits[1])
    ret['swpd'] = int(splits[2]) * vmstatBlockBytes
    ret['free'] = int(splits[3]) * vmstatBlockBytes
    ret['buff'] = int(splits[4]) * vmstatBlockBytes
    ret['cache'] = int(splits[5]) * vmstatBlockBytes
    ret['si'] = int(splits[6]) * vmstatBlockBytes
    ret['so'] = int(splits[7]) * vmstatBlockBytes
    ret['bi'] = int(splits[8]) * vmstatBlockBytes
    ret['bo'] = int(splits[9]) * vmstatBlockBytes
    ret['in'] = int(splits[10])
    ret['cs'] = int(splits[11])
    ret['us'] = int(splits[12])
    ret['sy'] = int(splits[13])
    ret['id'] = int(splits[14])
    ret['wa'] = int(splits[15])
    ret['st'] = int(splits[16])

    return time, ret


def insertOneVmstatLine(line):  # TODO use COPY or prepared statements
    sqlInsert = "insert into {} select %s, %s, %s, %s where not exists (select * from {} where time = %s and dbname = %s)".format(PGWATCH2_METRIC_NAME, PGWATCH2_METRIC_NAME)
    time, lineDict = parseVmstatLineToDict(line)
    if lineDict and time:
        logging.info('storing line: %s', lineDict)
        ensureSubpartition(args.pgwatch2_dbname, time)
        executeSQL(sqlInsert, (time, args.pgwatch2_dbname, psycopg2.extras.Json(lineDict), args.pgwatch2_tag_data, time, args.pgwatch2_dbname), connection=metricsDBConn, async_commit=True)


if __name__ == '__main__':

    argp = argparse.ArgumentParser(description='''Parse a 'vmstat [-w] -t $interval' output text file and insert the data into pgwatch2 Postgres metrics DB''')
    argp.add_argument('-f', '--file', dest='file', required=True, help='''Path to the vmstat log file or '-' for stdin piping''')
    argp.add_argument('--pgwatch2-dbname', dest='pgwatch2_dbname', required=True, help='''The host name / unique DB name on pgwatch2 side''')
    argp.add_argument('--pgwatch2-tag-data', dest='pgwatch2_tag_data', default=None, help='''In JSON format''')
    argp.add_argument('--vmstat-unit', dest='vmstat_unit', default='K', help='''Vmstat -S / --unit parameter. Default is 'K' ~ 1024 bytes per reported block''')
    # pgwatch2 metrics DB connect info
    argp.add_argument('-H', '--host', dest='host', default='localhost')
    argp.add_argument('-d', '--dbname', dest='dbname', required=True)
    argp.add_argument('-p', '--port', dest='port', type=int, default=5432)
    argp.add_argument('-U', '--user', dest='user')
    argp.add_argument('-v', '--verbose', dest='verbose', action='store_true', default=False)
    args = argp.parse_args()

    if not args.user:
        args.user = os.getenv('PGUSER')
        if not args.user:
            args.user = os.getenv('USER')
    if args.vmstat_unit and not args.vmstat_unit in VMSTAT_BYTE_UNITS:
        print('--vmstat-unit must be one of:', VMSTAT_BYTE_UNITS.keys())
        exit(1)
    else:
        global vmstat_block_bytes
        vmstatBlockBytes = VMSTAT_BYTE_UNITS[args.vmstat_unit]

    logging.basicConfig(format='%(asctime)s %(message)s', level=(logging.DEBUG if args.verbose else logging.WARNING))

    # test connection to pgwatch2 metric storage DB + ensure our PGWATCH2_METRIC_NAME table
    logging.info('checking DB connection...')
    executeSQL('select admin.ensure_dummy_metrics_table(%s)', (PGWATCH2_METRIC_NAME,), quiet=True)
    logging.info('OK')

    fp = None
    if args.file != '-':
        if not os.path.exists(args.file):
            logging.fatal('input file not found: %s', args.file)
        else:
            fp = open(args.file)
            metricsDBConn = getPGConnection()
            logging.info('DB conn: %s', metricsDBConn)

    # main loop
    while True:
        if args.file == '-':
            line = sys.stdin.readline()
        else:
            line = fp.readline()
        if not line:
            logging.info("reached EOF. lines processed: %s", linesProcessed)
            sys.exit()

        insertOneVmstatLine(line)
