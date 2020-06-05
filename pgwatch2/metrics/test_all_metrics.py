#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# auto-detects PG ver, and executes all found metrics discarding data, but reporting errors.

import glob
import re
import psycopg2
import psycopg2.extras
import os
import sys
import argparse
import logging
import yaml
from pathlib import Path

SPECIAL_METRICS = ['change_events']
ALLOWED_RETURN_DATATYPES = {16: 'bool', 18: 'char', 20: 'int8', 23: 'int4', 25: 'text', 700: 'float4', 701: 'float8', 1043: 'varchar', 1114: 'timestamp', 1184: 'timestamptz'}

args = None
datatype_failures=0


def executeOnRemoteHost(sql, host, port, dbname, user, password='', sslmode='prefer', sslrootcert='', sslcert='', sslkey='', params=None, statement_timeout=None, quiet=False, check_datatypes=False, metric=''):
    result = []
    conn = None

    try:
        # logging.debug('executing query on %s@%s/%s:', host, port, dbname)
        # logging.debug(sql)
        conn = psycopg2.connect(host=host, port=port, dbname=dbname, user=user, password=password,
            sslmode=sslmode, sslrootcert=sslrootcert, sslcert=sslcert, sslkey=sslkey)
        conn.autocommit = True
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        if statement_timeout:
            cur.execute("SET statement_timeout TO '{}'".format(
                statement_timeout))
        cur.execute(sql, params)
        if check_datatypes:
            for c in cur.description:
                 if c.type_code not in ALLOWED_RETURN_DATATYPES:
                    logging.error('invalid data type returned for "%s": column=%s, oid=%s', metric, c.name, c.type_code)
                    global datatype_failures
                    datatype_failures += 1
#                 else:
#                     logging.info('%s data type is %s', c.name, ALLOWED_RETURN_DATATYPES[c.type_code])
        if cur.statusmessage.startswith('SELECT') or cur.description:
            result = cur.fetchall()
        else:
            result = [{'rows_affected': str(cur.rowcount)}]
    except Exception as e:
        if quiet:
            return result, str(e)
        else:
            logging.exception('failed to execute "{}" on remote host "{}:{}"'.format(sql, host, port))
            raise
    finally:
        if conn:
            try:
                conn.close()
            except:
                logging.exception('failed to close connection')
    return result, None


def get_pg_version_as_text(host, port, user, password=''):
    sql = """select (regexp_matches(
                        regexp_replace(current_setting('server_version'), '(beta|devel).*', '', 'g'),
                        E'\\\\d+\\\\.?\\\\d+?')
                        )[1]::text as ver, not pg_is_in_recovery() as is_primary"""

    logging.debug('getting PG version info from %s@%s...', host, port)
    data, err = executeOnRemoteHost(sql, host, port, 'template1', user, password, quiet=True)
    if err:
        logging.debug('could not get PG version from %s@%s: %s', host, port, err)
        return '', False
    ver_full = data[0]['ver']  # will be in form of 10.11
    is_primary = data[0]['is_primary']
    s = ver_full.split('.')
    if int(s[0]) >= 10:
        return s[0], is_primary
    else:
        return s[0] + '.' + s[1], is_primary


def get_metrics_from_filesystem(target_pgver, is_primary):
    ret = []    # [{'metric': 'get_x', 'sql': 'select ...', ...}
    target_pgver = float(target_pgver)
    metrics = glob.glob(os.path.join(args.metrics_path, '*'))

    for m in metrics:
        if not os.path.isdir(m):
            continue
        if m in SPECIAL_METRICS:
            continue
        vers = os.listdir(m)
        numeric_vers = []
        for v in vers:
            try:
                v_float = float(v)
            except:
                continue
            numeric_vers.append((v, v_float))
        if len(numeric_vers) == 0:
            continue

        numeric_vers.sort(key=lambda x: x[1])

        best_matching_pgver = None
        for nv, nv_float in numeric_vers:
            if target_pgver >= nv_float:
                best_matching_pgver = nv
        if not best_matching_pgver:
            logging.warning('could not find suitable metric for "%s" target ver %s, skipping', m, target_pgver)
            continue        
        # logging.warning('found suitable helper for %s target ver %s', h, best_matching_pgver)
        
        metric_def_file = os.path.join(m, str(best_matching_pgver), 'metric.sql')
        if not os.path.exists(metric_def_file):
            if is_primary:
                metric_def_file = os.path.join(m, str(best_matching_pgver), 'metric_master.sql')
            else:
                metric_def_file = os.path.join(m, str(best_matching_pgver), 'metric_standby.sql')
            if not os.path.exists(metric_def_file):
                logging.warning('could not find suitable metric for "%s", target ver %s, is_primary = %s. skipping', m, target_pgver, is_primary)
                continue    			
        
        with open(metric_def_file, 'r') as f:
            sql = f.read()
        if not sql:
            logging.info('ignoring due to empty SQL. metric "%s", target ver %s, is_primary = %s. skipping', m, target_pgver, is_primary)
            continue

        ret.append({'metric': Path(m).stem, 'sql': sql})

    ret.sort(key=lambda x: x['metric'])
    return ret


def main():
    argp = argparse.ArgumentParser(description='Roll out pgwatch2 metric fetching helpers to all monitored DB-s configured in config DB or to a specified DB / instance (all DBs)')

    argp.add_argument('--metrics-path', dest='metrics_path', default='.', help='Path to the folder containing metric definitions. Current working directory by default')
    # target db connect info
    argp.add_argument('--host', dest='host', help='Host address for explicit single DB / instance rollout', required=True)
    argp.add_argument('--port', dest='port', default=5432, type=int, help='Port for explicit single DB / instance rollout')
    argp.add_argument('--dbname', dest='dbname', help='Explicit dbname for rollout', required=True)
    argp.add_argument('-U', '--user', dest='user', help='Superuser username for helper function creation')
    argp.add_argument('--password', dest='password', default='', help='Superuser password for helper function creation. The .pgpass file can also be used instead')
    argp.add_argument('-v', '--verbose', dest='verbose', action='store_true', default=False, help='More chat')

    global args
    args = argp.parse_args()

    logging.basicConfig(format='%(message)s', level=(logging.DEBUG if args.verbose else logging.WARNING))

    if not args.user:
        args.user = (os.getenv('PGUSER') or os.getenv('USER'))

    logging.debug(args)

    pgver, is_primary = get_pg_version_as_text(args.host, args.port, args.user, args.password)
    if pgver == '':
        logging.fatal('Failed to determine pg version')
        sys.exit(1)
    logging.warning('DB is on version %s', pgver)
    
    metrics = get_metrics_from_filesystem(pgver, is_primary)
    logging.info('Found %s metrics', len(metrics))

    ok = 0
    failed_metrics = []
    for i, m in enumerate(metrics):
        metric = m['metric']
        sql = m['sql']
        logging.info('testing "%s", sql:', metric)
        logging.info(sql)
        data, err = executeOnRemoteHost(sql, args.host, args.port, args.dbname, args.user, args.password, quiet=True, check_datatypes=True, metric=metric)
        if err:
            logging.info('************')
            logging.warning('failed to fetch "%s": %s', metric, err)
            logging.info('************')
            failed_metrics.append(metric)
        else:
            logging.info('fetch from "%s" succeeded', metric)
            ok += 1

    logging.warning('%s / %s metric fetches succeeded', ok, len(metrics))
    logging.warning('failed metrics: %s', failed_metrics)
    logging.warning('invalid column data types: %s', datatype_failures)
    logging.info('done')
    if datatype_failures > 0 or ok < len(metrics):
        sys.exit(1)


if __name__ == '__main__':
    main()

# TODO - measure timings and report longer ones