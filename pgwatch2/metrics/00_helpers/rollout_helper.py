#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# auto-detects PG ver, rolls-out all helpers not in exlude list, reports errors summary. dry-run first
# can only read monitoring DBs config from config DB or when specified per single DB / instance
import glob
import re
import psycopg2
import psycopg2.extras
import os
import argparse
import logging
import yaml
from pathlib import Path

args = None


def executeOnRemoteHost(sql, host, port, dbname, user, password='', sslmode='prefer', sslrootcert='', sslcert='', sslkey='', params=None, statement_timeout=None, quiet=False, target_schema=''):
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
        if target_schema:
            cur.execute("SET search_path TO {}".format(
                target_schema))
        cur.execute(sql, params)
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


# get real names if dbtype = 'postgres-continuous-discovery'
def resolve_configdb_host_to_dbs(md_entry):
    ret = []
    sql_all_enabled_dbs_on_instance = "select datname from pg_database where not datistemplate and datallowconn order by 1"

    if md_entry['md_dbtype'] == 'postgres':
        ret.append(md_entry)
    elif md_entry['md_dbtype'] == 'postgres-continuous-discovery':
        all_dbs, err = executeOnRemoteHost(sql_all_enabled_dbs_on_instance, md_entry['md_hostname'], md_entry['md_port'], 'template1', args.user, args.password, quiet=True)
        if err:
            logging.error('could not fetch DB listing from %s@%s: %s', md_entry['md_hostname'], md_entry['md_port'], err)
        else:
            for db in all_dbs:
                e = md_entry.copy()
                e['md_dbname'] = db['datname']
                e['md_dbtype'] = 'postgres'
                ret.append(e)

    return ret


def get_active_dbs_from_configdb():
    ret = []
    sql = """select md_unique_name, md_hostname, md_port, md_dbname, md_user, md_password, md_sslmode, md_dbtype from pgwatch2.monitored_db where md_is_enabled and md_dbtype in ('postgres') order by 1"""
    md_entries, err = executeOnRemoteHost(sql, args.configdb_host, args.configdb_port, args.configdb_dbname, args.configdb_user, args.configdb_password)
    if err:
        logging.fatal('could not connect to configDB: %s', err)
        exit(1)
    for md in md_entries:
        logging.debug('found entry from config DB: hostname=%s, port=%s, dbname=%s, dbtype=%s, user=%s', md['md_hostname'], md['md_port'], md['md_dbname'], md['md_dbtype'], md['md_user'])
        [ret.append(e) for e in resolve_configdb_host_to_dbs(md)]
    return ret


def get_helper_sqls_from_configdb(pgver):   # TODO caching
    sql = """select distinct on (m_name) m_name as helper, m_sql as sql from metric where m_is_helper and m_is_active and m_pg_version_from <= %s order by m_name, m_pg_version_from desc;"""
    helpers, err = executeOnRemoteHost(sql, args.configdb_host, args.configdb_port, args.configdb_dbname, args.configdb_user, args.configdb_password, params=(pgver,))
    if err:
        logging.fatal('could not connect to configDB: %s', err)
        exit(1)
    return helpers


def do_roll_out(md, pgver):
    ok = 0
    total = 0

    if args.metrics_path:
        helpers = get_helpers_from_filesystem(pgver)
    else:
        helpers = get_helper_sqls_from_configdb(pgver)
    if args.helpers or args.excluded_helpers:    # filter out unwanted helpers
        helpers_filtered = []
        if args.helpers:
            wanted_helpers = args.helpers.split(',')
            [helpers_filtered.append(h) for h in helpers if h['helper'] in wanted_helpers]
        else:
            unwanted_helpers = args.excluded_helpers.split(',')
            [helpers_filtered.append(h) for h in helpers if h['helper'] not in unwanted_helpers]
        helpers = helpers_filtered

    for hp in helpers:
        sql = hp['sql']
        if args.monitoring_user != 'pgwatch2':  # change helper definitions so that 'grant execute' is done for the monitoring role specified in the configuration
            sql = re.sub(r'(?i)TO\s+pgwatch2', 'TO ' + args.monitoring_user, sql)
        if args.python2:
            sql = sql.replace('plpython3u', 'plpythonu')

        all_dbs, err = executeOnRemoteHost(sql, md['md_hostname'], md['md_port'], md['md_dbname'], args.user, args.password, quiet=True, target_schema=args.target_schema)
        if err:
            logging.debug('failed to roll out %s: %s', hp['helper'], err)
        else:
            ok += 1
            logging.debug('rollout of %s succeeded', hp['helper'])
        total += 1
    return ok, total


def get_helpers_from_filesystem(target_pgver):
    ret = []    # [{'helper': 'get_x', 'sql': 'create ...',...}
    target_pgver = float(target_pgver)
    helpers = glob.glob(os.path.join(args.metrics_path, '*'))

    for h in helpers:
        if not os.path.isdir(h):
            continue
        vers = os.listdir(h)
        numeric_vers = []
        for v in vers:
            try:
                v_float = float(v)
            except:
                continue
            if v_float >= 10 and h.endswith(".0"):
                h = h.replace(".0", "")
            numeric_vers.append((v, v_float))
        if len(numeric_vers) == 0:
            continue

        numeric_vers.sort(key=lambda x: x[1])

        best_matching_pgver = None
        for nv, nv_float in numeric_vers:
            if target_pgver >= nv_float:
                best_matching_pgver = nv
        if not best_matching_pgver:
            logging.warning('could not find suitable helper for %s target ver %s, skipping', h, target_pgver)
            continue
        # logging.warning('found suitable helper for %s target ver %s', h, best_matching_pgver)
        with open(os.path.join(h, str(best_matching_pgver), 'metric.sql'), 'r') as f:
            sql = f.read()
        ret.append({'helper': Path(h).stem, 'sql': sql})

    ret.sort(key=lambda x: x['helper'])
    return ret


# TODO handle libpq_conn_str
def get_monitored_dbs_from_yaml_config():   # active entries ("is_enabled": true) only. configs can be in subfolders also - all YAML/YML files will be searched for
    ret = []

    for root, dirs, files in os.walk(args.config_path):
        for f in files:
            if f.lower().endswith('.yml') or f.lower().endswith('.yaml'):
                logging.debug('found a config file: %s', os.path.join(root, f))
                with open(os.path.join(root, f), 'r') as fp:
                    config = fp.read()
                try:
                    monitored_dbs = yaml.full_load(config)
                except:
                    logging.error("skipping config file %s as could not parse YAML")
                    continue
                if not monitored_dbs or not type(monitored_dbs) == list:
                    continue
                for db in monitored_dbs:
                    if db.get('is_enabled'):
                        md = {'md_hostname': db.get('host'), 'md_port': db.get('port', 5432), 'md_dbname': db.get('dbname'),
                              'md_user': db.get('user'), 'md_password': db.get('password'),
                              'md_unique_name': db.get('unique_name'),
                              'md_dbtype': db.get('dbtype')}
                        [ret.append(e) for e in resolve_configdb_host_to_dbs(md)]

    ret.sort(key=lambda x: x['md_unique_name'])
    return ret


def main():
    argp = argparse.ArgumentParser(description='Roll out pgwatch2 metric fetching helpers to all monitored DB-s configured in config DB or to a specified DB / instance (all DBs)')

    # to use file based helper / config definitions
    argp.add_argument('--metrics-path', dest='metrics_path', default='.', help='Path to the folder containing helper definitions. Current working directory by default')
    argp.add_argument('--config-path', dest='config_path', default='', help='Path including YAML based monitoring config files. Subfolders are supported the same as with collector')

    # pgwatch2 config db connect info
    argp.add_argument('--configdb-host', dest='configdb_host', default='', help='pgwatch2 config DB host address')
    argp.add_argument('--configdb-dbname', dest='configdb_dbname', default='pgwatch2', help='pgwatch2 config DB dbname (relevant in configdb mode)')
    argp.add_argument('--configdb-port', dest='configdb_port', default='5432', help='pgwatch2 config DB port (relevant in configdb mode)')
    argp.add_argument('--configdb-user', dest='configdb_user', default='postgres', help='pgwatch2 config DB user (relevant in configdb mode)')
    argp.add_argument('--configdb-password', dest='configdb_password', default='', help='pgwatch2 config DB password (relevant in configdb mode)')

    # rollout target db connect info
    argp.add_argument('--host', dest='host', help='Host address for explicit single DB / instance rollout')
    argp.add_argument('--port', dest='port', default=5432, type=int, help='Port for explicit single DB / instance rollout')
    argp.add_argument('--dbname', dest='dbname', help='Explicit dbname for rollout')
    argp.add_argument('-U', '--user', dest='user', help='Superuser username for helper function creation')
    argp.add_argument('--password', dest='password', default='', help='Superuser password for helper function creation. The .pgpass file can also be used instead')
    argp.add_argument('--monitoring-user', dest='monitoring_user', default='pgwatch2', help='The user getting execute privileges to created helpers (relevant for single or instance mode)')
    argp.add_argument('--target-schema', dest='target_schema', default='', help='If specified, used to set the search_path')

    argp.add_argument('-c', '--confirm', dest='confirm', action='store_true', default=False, help='perform the actual rollout')
    argp.add_argument('-m', '--mode', dest='mode', default='', help='[configdb-all|yaml-all|single-db|single-instance]')
    argp.add_argument('--helpers', dest='helpers', help='Roll out only listed (comma separated) helpers. By default all will be tried to roll out')
    argp.add_argument('--excluded-helpers', dest='excluded_helpers', default='get_load_average_windows,get_load_average_copy,get_smart_health_per_device', help='Do not try to roll out these by default. Clear list if needed')
    argp.add_argument('--template1', dest='template1', action='store_true', default=False, help='Install helpers into template1 so that all newly craeted DBs will get them automatically')
    argp.add_argument('--python2', dest='python2', action='store_true', default=False, help='Use Python v2 (EOL) instead of default v3 in PL/Python helpers')
    argp.add_argument('-v', '--verbose', dest='verbose', action='store_true', default=False, help='More chat')

    rollout_dbs = []
    unique_host_port_pairs = set()

    global args
    args = argp.parse_args()

    logging.basicConfig(format='%(message)s', level=(logging.DEBUG if args.verbose else logging.WARNING))

    if not args.mode or not args.mode.lower() in ['configdb-all', 'yaml-all', 'single-db', 'single-instance']:
        logging.fatal('invalid --mode param value "%s". must be one of: [configdb-all|single-db|instance]', args.mode)
        logging.fatal('     configdb-all - roll out helpers to all active DBs defined in pgwatch2 config DB')
        logging.fatal('     yaml-all - roll out helpers to all active DBs defined in YAML configs')
        logging.fatal('     single-db - roll out helpers on a single DB specified by --host, --port (5432*), --dbname and --user params')
        logging.fatal('     single-instance - roll out helpers on all DB-s of an instance specified by --host, --port (5432*) and --user params')
        exit(1)

    if args.mode.lower() == 'configdb-all' and not args.configdb_host:
        logging.fatal('--configdb-host parameter required with --configdb-all')
        exit(1)

    if args.mode.lower() == 'yaml-all' and not args.config_path:
        logging.fatal('--config-path parameter (YAML definitions on monitored instances) required for \'yaml-all\' mode')
        exit(1)

    if not args.configdb_host and not args.metrics_path:
        logging.fatal('one of --configdb-host or --metrics-path needs to be always specified')
        exit(1)

    if args.mode == 'single-db' and not (args.host and args.user and args.dbname):
        logging.fatal('--host, --dbname, --user must be specified for explicit single DB rollout')
        exit(1)
    if args.mode == 'single-instance' and not (args.host and args.user):
        logging.fatal('--host and --user must be specified for explicit single instance rollout')
        exit(1)

    if not args.user:
        args.user = os.getenv('PGUSER') or os.getenv('USER')

    logging.debug(args)

    if not args.confirm:
        logging.warning('starting in DRY-RUN mode, add --confirm to execute')

    if args.mode == 'configdb-all':
        rollout_dbs = get_active_dbs_from_configdb()
    elif args.mode == 'yaml-all':
        rollout_dbs = get_monitored_dbs_from_yaml_config()
    else:
        md = {'md_hostname': args.host, 'md_port': args.port, 'md_dbname': args.dbname, 'md_user': args.user, 'md_password': args.password,
              'md_unique_name': 'ad-hoc', 'md_dbtype': 'postgres-continuous-discovery' if args.mode == 'single-instance' else 'postgres'}
        if args.mode == 'single-instance':
            rollout_dbs = resolve_configdb_host_to_dbs(md)
        else:   # single DB
            rollout_dbs = [md]

    logging.warning('*** ROLLOUT TO TARGET DB-s ***')
    for i, db in enumerate(rollout_dbs):
        pgver, is_primary = get_pg_version_as_text(db['md_hostname'], db['md_port'], args.user, args.password)
        if pgver == '':
            logging.error('DB #%s: [%s] failed to determine pg version for %s@%s, skipping rollout', i, db['md_unique_name'], db['md_hostname'], db['md_port'])
            continue
        if not is_primary:
            logging.info('DB #%s: [%s] %s@%s skipping as not a primary', i, db['md_unique_name'], db['md_hostname'], db['md_port'])
            continue
        logging.warning('DB #%s: [%s] %s@%s/%s on version %s', i, db['md_unique_name'], db['md_hostname'], db['md_port'], db['md_dbname'], pgver)

        if args.confirm:
            ok, total = do_roll_out(db, pgver)
            logging.warning('%s / %s succeeded', ok, total)

            if args.template1 and (db['md_hostname'], db['md_port']) not in unique_host_port_pairs: # try template1 rollout only once per instance
                db_t1 = db.copy()
                db_t1['md_dbname'] = 'template1'
                logging.warning('DB #%s TEMPLATE1: [%s] %s@%s/%s on version %s', i, db['md_unique_name'], db['md_hostname'],
                                db['md_port'], db_t1['md_dbname'], pgver)
                ok_t1, total_t1 = do_roll_out(db_t1, pgver)
                ok += ok_t1
                total += total_t1
                logging.warning('%s / %s succeeded', ok_t1, total_t1)

                unique_host_port_pairs.add((db['md_hostname'], db['md_port']))

    logging.info('done')


if __name__ == '__main__':
    main()
