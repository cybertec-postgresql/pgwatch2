#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# auto-detects PG ver, rolls-out all helpers not in exlude list, reports errors summary. dry-run first
# can only read monitoring DBs config from config DB or when specified per single DB / instance

import re
import psycopg2
import psycopg2.extras
import os
import argparse
import logging
# import yaml


args = None


def executeOnRemoteHost(sql, host, port, dbname, user, password='', sslmode='prefer', sslrootcert='', sslcert='', sslkey='', params=None, statement_timeout=None, quiet=False):
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

        all_dbs, err = executeOnRemoteHost(sql, md['md_hostname'], md['md_port'], md['md_dbname'], args.user, args.password, quiet=True)
        if err:
            logging.debug('failed to roll out %s: %s', hp['helper'], err)
        else:
            ok += 1
            logging.debug('rollout of %s succeeded', hp['helper'])
        total += 1
    return ok, total


def get_helpers_from_filesystem(pgver):  # TODO
    pass


def get_dbs_from_yaml_config(): # TODO
    ret = []
# config = yaml.load(open(args.config))
# logging.info('Read config %s', config)
    return ret


def main():
    argp = argparse.ArgumentParser(description='Roll out pgwatch2 metric fetching helpers to all monitored DB-s configured in config DB or to a specified DB / instance (all DBs)')

    # pgwatch2 config db connect info
    argp.add_argument('--configdb-host', dest='configdb_host', default='', help='pgwatch2 config DB host (relevant in configdb mode)')
    argp.add_argument('--configdb-dbname', dest='configdb_dbname', default='pgwatch2', help='pgwatch2 config DB dbname (relevant in configdb mode)')
    argp.add_argument('--configdb-port', dest='configdb_port', default='5432', help='pgwatch2 config DB port (relevant in configdb mode)')
    argp.add_argument('--configdb-user', dest='configdb_user', default='postgres', help='pgwatch2 config DB user (relevant in configdb mode)')
    argp.add_argument('--configdb-password', dest='configdb_password', default='', help='pgwatch2 config DB password (relevant in configdb mode)')

    # rollout target db connect info
    argp.add_argument('-U', '--user', dest='user', default='postgres', help='Superuser username for helper function creation')
    argp.add_argument('--password', dest='password', default='', help='Password for connecting to configDB + instances defined there. Leave empty to let .pgpass take effect')
    argp.add_argument('--monitoring-user', dest='monitoring_user', default='pgwatch2', help='The user getting execute privileges to created helpers (relevant for single or instance mode)')

    argp.add_argument('-c', '--confirm', dest='confirm', action='store_true', default=False, help='perform the actual rollout')
    argp.add_argument('-m', '--mode', dest='mode', default='configdb', help='[configdb|single|instance] - instance = all non-template DBs')
    argp.add_argument('--helpers', dest='helpers', help='Roll out only listed (comma separated) helpers. By default all will be tried to roll out')
    argp.add_argument('--excluded-helpers', dest='excluded_helpers', default='get_load_average_windows,get_load_average_copy,get_smart_health_per_device', help='Do not try to roll out these by default. Clear list if needed')
    argp.add_argument('--template1', dest='template1', action='store_true', default=False, help='Install helpers into template1 so that all newly craeted DBs will get them automatically') # TODO
    argp.add_argument('--python2', dest='python2', action='store_true', default=False, help='Use Python v2 (EOL) instead of default v3 in PL/Python helpers')
    argp.add_argument('-v', '--verbose', dest='verbose', action='store_true', default=False, help='More chat')

    rollout_dbs = []
    global args
    args = argp.parse_args()

    logging.basicConfig(format='%(message)s', level=(logging.DEBUG if args.verbose else logging.WARNING))

    if not args.mode or not args.mode.lower() in ['configdb', 'single', 'instance']:
        logging.fatal('unknown --mode param value "%s". can be one of: [configdb|single|instance]', args.mode)
        exit(1)
    if args.mode == 'configdb' and not args.configdb_host:
        logging.fatal('--configdb-host required when --mode=configdb')
        exit(1)

    if not args.user:
        args.user = os.getenv('PGUSER') or os.getenv('USER')

    logging.debug(args)

    if not args.confirm:
        logging.warning('starting in DRY-RUN mode, add --confirm to execute')

    if args.mode == 'configdb':
        rollout_dbs = get_active_dbs_from_configdb()
    else:
        md = {'md_hostname': args.host, 'md_port': args.port, 'md_dbname': args.dbname, 'md_port': args.port, 'md_user': args.user, 'md_password': args.password,
         'md_unique_name': 'ad-hoc', 'md_dbtype': 'postgres-continuous-discovery' if args.mode == 'instance' else 'postgres'}
        if args.mode == 'instance':
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

    logging.info('done')


if __name__ == '__main__':
    main()
