#!/usr/bin/env python3

import json
import os
from argparse import ArgumentParser
import logging
from datetime import datetime, timedelta
from pathlib import Path
import cherrypy
import time
import datadb
import pgwatch2_influx
import psycopg2
import requests
from decorator import decorator
import subprocess
import utils

import pgwatch2
from jinja2 import Environment, FileSystemLoader

env = Environment(loader=FileSystemLoader(
    os.path.join(str(Path(__file__).parent), 'templates')))
cmd_args = None


@decorator
def logged_in(f: callable, *args, **kwargs):
    if cmd_args.no_anonymous_access:
        if not cherrypy.session.get('logged_in'):
            url = cherrypy.url()    # http://0.0.0.0:8080/dbs
            splits = url.split('/') # ['https:', '', '0.0.0.0:8080', 'dbs']
            if len(splits) > 3 and splits[3] in ['dbs', 'metrics', 'logs']:
                raise cherrypy.HTTPRedirect('/login' + ('?returl=/' + '/'.join(splits[3:])))
            else:
                raise cherrypy.HTTPRedirect('/login')
    return f(*args, **kwargs)


def exec_cmd(args, silent=True):
    if silent:
        try:
            p = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            return p.stdout.decode('utf-8'), p.stderr.decode('utf-8')
        except Exception as e:
            return '', str(e)
    else:
        p = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        return p.stdout.decode('utf-8'), p.stderr.decode('utf-8')


def str_to_bool_or_fail(bool_str):
    if bool_str is None:
        return None
    if bool_str.strip() == '' or bool_str.strip() == '""' or bool_str.strip() == "''":
        return False
    if bool_str.lower().strip() in ['t', 'true', 'y', 'yes', 'on', 'require', '1']:
        return True
    if bool_str.lower().strip() in ['f', 'false', 'n', 'no', 'off', 'disable', '0']:
        return False
    else:
        raise Exception('Boolean string (or empty/quotes) expected! Found: ' + bool_str)


class Root:

    @cherrypy.expose
    def login(self, **params):
        message = ''
        submit = params.get('submit', False)
        user = params.get('user', '')
        password = params.get('password', '')
        returl = params.get('returl')

        if not cmd_args.no_anonymous_access:
            raise cherrypy.HTTPRedirect('/index')

        if submit:
            if user and password:
                if user == cmd_args.admin_user and password == cmd_args.admin_password:
                    # default, in-memory sessions
                    cherrypy.session['logged_in'] = True
                    cherrypy.session['login_time'] = time.time()
                    raise cherrypy.HTTPRedirect(returl if returl else '/index')
                else:
                    message = 'Wrong username and/or password!'
            else:
                message = 'Username and password needed!'
        tmpl = env.get_template('login.html')
        return tmpl.render(message=message, user=user, returl=returl)

    @cherrypy.expose
    def logout(self, **params):
        if 'logged_in' in cherrypy.session:
            del cherrypy.session['logged_in']
        raise cherrypy.HTTPRedirect('/dbs')

    @logged_in
    @cherrypy.expose
    def dbs(self, **params):
        logging.debug(params)
        messages = []
        data = []
        preset_configs = []
        metrics_list = []
        active_dbnames = []
        preset_configs_json = {}

        if params:
            try:
                if params.get('save'):
                    messages += pgwatch2.update_monitored_db(params, cmd_args)
                elif params.get('new'):
                    messages += pgwatch2.insert_monitored_db(params, cmd_args)
                elif params.get('delete'):
                    pgwatch2.delete_monitored_db(params)
                    messages.append('Entry with ID {} ("{}") deleted!'.format(
                        params['md_id'], params['md_unique_name']))
                elif params.get('delete_single'):
                    if not params['single_unique_name']:
                        raise Exception('No "Unique Name" provided!')
                    if cmd_args.datastore == 'influx':
                        pgwatch2_influx.delete_influx_data_single(params['single_unique_name'])
                    else:
                        pgwatch2.delete_postgres_metrics_data_single(params['single_unique_name'])
                    messages.append('Data for "{}" deleted!'.format(params['single_unique_name']))
                elif params.get('delete_all'):
                    active_dbs = pgwatch2.get_active_db_uniques()
                    if cmd_args.datastore == 'influx':
                        deleted_dbnames = pgwatch2_influx.delete_influx_data_all(active_dbs)
                    else:
                        deleted_dbnames = pgwatch2.delete_postgres_metrics_for_all_inactive_hosts(active_dbs)
                    messages.append('Data deleted for: {}'.format(','.join(deleted_dbnames)))
                elif params.get('disable_all'):
                    affected = pgwatch2.disable_all_dbs()
                    messages.append('{} DBs disabled. It will take some minutes for this to become effective'.format(affected))
                elif params.get('enable_all'):
                    affected = pgwatch2.enable_all_dbs()
                    messages.append('{} DBs enabled'.format(affected))
                elif params.get('set_bulk_config'):
                    affected = pgwatch2.set_bulk_config(params)
                    messages.append("'{}' preset set as config for {} DBs. It will take some minutes for this to become effective".format(params.get('bulk_preset_config_name'), affected))
                elif params.get('set_bulk_timeout'):
                    affected = pgwatch2.set_bulk_timeout(params)
                    messages.append("Timeout set for {} DBs".format(affected))
                elif params.get('set_bulk_password'):
                    err, affected = pgwatch2.set_bulk_password(params, cmd_args)
                    if err:
                        messages.append(err)
                    else:
                        messages.append("Password updated for {} DBs".format(affected))
            except Exception as e:
                logging.exception('Changing DBs failed')
                messages.append('ERROR: ' + str(e))

        try:
            active_dbnames = pgwatch2_influx.get_active_dbnames() if cmd_args.datastore == 'influx' else pgwatch2.get_all_dbnames()
        except Exception as e:
            logging.exception(e)
            messages.append(str(e))
        except Exception as e:
            logging.exception('ERROR getting DB listing from metrics DB')
            messages.append('ERROR getting DB listing from metrics DB: ' + str(e))

        try:
            data = pgwatch2.get_all_monitored_dbs()
            preset_configs = pgwatch2.get_preset_configs()
            preset_configs_json = json.dumps(
                {c['pc_name']: c['pc_config'] for c in preset_configs})
            metrics_list = pgwatch2.get_active_metrics_with_versions()
        except psycopg2.OperationalError:
            messages.append('ERROR: Could not connect to Postgres')
        except Exception as e:
            messages.append('ERROR: ' + str(e))

        tmpl = env.get_template('dbs.html')
        return tmpl.render(messages=messages, data=data, preset_configs=preset_configs, preset_configs_json=preset_configs_json,
                           metrics_list=metrics_list, active_dbnames=active_dbnames,
                           no_anonymous_access=cmd_args.no_anonymous_access, session=cherrypy.session,
                           no_component_logs=cmd_args.no_component_logs, aes_gcm_enabled=cmd_args.aes_gcm_keyphrase,
                           datastore=cmd_args.datastore)

    @logged_in
    @cherrypy.expose
    def metrics(self, **params):
        logging.debug(params)
        messages = []
        preset_configs = []
        metrics_list = []
        metric_definitions = []

        try:
            if params.get('save'):
                pgwatch2.update_preset_config(params)
                messages.append('Config "{}" updated!'.format(params['pc_name']))
            elif params.get('new'):
                config = pgwatch2.insert_preset_config(params)
                messages.append('Config "{}" added!'.format(config))
            elif params.get('delete'):
                pgwatch2.delete_preset_config(params)
                messages.append('Config "{}" deleted!'.format(params['pc_name']))
            if params.get('metric_save'):
                msg = pgwatch2.update_metric(params)
                messages.append('Metric "{}" updated!'.format(params['m_name']))
                if msg:
                    messages.append(msg)
            elif params.get('metric_new'):
                id, msg = pgwatch2.insert_metric(params)
                messages.append('Metric with ID "{}" added!'.format(id))
                if msg:
                    messages.append(msg)
            elif params.get('metric_delete'):
                msg = pgwatch2.delete_metric(params)
                messages.append('Metric "{}" deleted!'.format(params['m_name']))
                if msg:
                    messages.append(msg)

            preset_configs = pgwatch2.get_preset_configs()
            metrics_list = pgwatch2.get_active_metrics_with_versions()
            metric_definitions = pgwatch2.get_all_metrics()
        except psycopg2.OperationalError:
            messages.append('ERROR: Could not connect to Postgres')
        except Exception as e:
            messages.append('ERROR: ' + str(e))

        tmpl = env.get_template('metrics.html')
        return tmpl.render(messages=messages, preset_configs=preset_configs, metrics_list=metrics_list,
                           metric_definitions=metric_definitions, no_anonymous_access=cmd_args.no_anonymous_access,
                           session=cherrypy.session, no_component_logs=cmd_args.no_component_logs
        )

    @logged_in
    @cherrypy.expose
    def logs(self, service='pgwatch2', lines=200):
        if cmd_args.no_component_logs:
            raise Exception('Component log access is disabled')
        if service not in pgwatch2.SERVICES:
            raise Exception('service needs to be one of: ' +
                            str(pgwatch2.SERVICES.keys()))

        log_lines = pgwatch2.get_last_log_lines(service, int(lines))

        cherrypy.response.headers['Content-Type'] = 'text/plain'
        return log_lines

    @logged_in
    @cherrypy.expose
    def versions(self):   # gives info on what's running inside docker
        ret = {}
        out, err = exec_cmd(['grafana-server', '-v'])
        ret['grafana'] = out.strip() + ('err: ' + err if len(err) > 3 else '')
        out, err = exec_cmd(['influxd', 'version'])
        ret['influxdb'] = out.strip() + ('err: ' + err if len(err) > 3 else '')
        out, err = exec_cmd(['cat', '/pgwatch2/build_git_version.txt'])
        ret['pgwatch2_git_version'] = out.strip(
        ) + ('err: ' + err if len(err) > 3 else '')
        data, err = datadb.execute('select version()')
        ret['postgres'] = data[0]['version'] if not err else err
        cherrypy.response.headers['Content-Type'] = 'text/plain'
        return json.dumps(ret)

    @cherrypy.expose
    def index(self, **params):
        return self.dbs(**params)

    @logged_in
    @cherrypy.expose
    def stats_summary(self, **params):
        if cmd_args.no_stats_summary:
            raise Exception('Displaying summary statistics has been disabled')

        logging.debug('params: %s', params)
        messages = []
        data = []
        dbnames = []
        dbname = params.get('dbname')
        page = params.get('page', 'stats-summary')
        sort_column = params.get('sort_column', 'total_time')
        start_time = params.get('start_time', '')
        end_time = params.get('end_time', '')

        try:
            if cmd_args.datastore not in ['influx', 'postgres']:
                raise Exception('Summary statistics only available for InfluxDB or Postgres data stores')

            if sort_column not in pgwatch2_influx.STATEMENT_SORT_COLUMNS:
                raise Exception('invalid "sort_column": ' + sort_column)

            if cmd_args.datastore == 'influx':
                dbnames = pgwatch2_influx.get_active_dbnames()
            else:
                dbnames = pgwatch2.get_all_dbnames()

            if dbname:
                if page == 'stats-summary' and dbname:
                    data = pgwatch2_influx.get_db_overview(dbname) if cmd_args.datastore == 'influx' else pgwatch2.get_db_overview(dbname)
                elif page == 'statements' and dbname:
                    if cmd_args.datastore == 'influx':
                        data = pgwatch2_influx.find_top_growth_statements(dbname,
                                                                      sort_column,
                                                                      start_time,
                                                                      (end_time if end_time else datetime.utcnow().isoformat() + 'Z'))
                    else:
                        data = pgwatch2.find_top_growth_statements(dbname,
                                                                      sort_column,
                                                                      start_time,
                                                                      (end_time if end_time else datetime.utcnow().isoformat() + 'Z'))
        except (requests.exceptions.ConnectionError, influxdb.exceptions.InfluxDBClientError):
            messages.append('ERROR - Could not connect to InfluxDB')
        except psycopg2.OperationalError:
            messages.append('ERROR - Could not connect to Postgres')
        except Exception as e:
            messages.append('ERROR - ' + str(e))

        tmpl = env.get_template('stats-summary.html')
        return tmpl.render(dbnames=dbnames, dbname=dbname, page=page, data=data, sort_column=sort_column,
                           start_time=start_time, end_time=end_time, grafana_baseurl=cmd_args.grafana_baseurl,
                           messages=messages, no_anonymous_access=cmd_args.no_anonymous_access, session=cherrypy.session,
                           no_component_logs=cmd_args.no_component_logs, datastore=cmd_args.datastore)


if __name__ == '__main__':
    parser = ArgumentParser(description='pgwatch2 Web UI')
    # Webserver
    parser.add_argument('--socket-host', help='Webserver Listen Address',
                        default=(os.getenv('PW2_WEBHOST') or '0.0.0.0'))
    parser.add_argument('--socket-port', help='Webserver Listen Port',
                        default=(os.getenv('PW2_WEBPORT') or 8080), type=int)
    parser.add_argument('--ssl', help='Enable Webserver SSL (Self-signed Cert)',
                        default=(str_to_bool_or_fail(os.getenv('PW2_WEBSSL')) or False))
    parser.add_argument('--ssl-cert', help='Path to SSL certificate',
                        default=(os.getenv('PW2_WEBCERT') or '/pgwatch2/persistent-config/self-signed-ssl.pem'))
    parser.add_argument('--ssl-key', help='Path to SSL private key',
                        default=(os.getenv('PW2_WEBKEY') or '/pgwatch2/persistent-config/self-signed-ssl.key'))
    parser.add_argument('--ssl-certificate-chain', help='Path to certificate chain file',
                        default=(os.getenv('PW2_WEBCERTCHAIN')))

    # PgWatch2
    parser.add_argument(
        '-v', '--verbose', help='Chat level. none(default)|-v|-vv [$PW2_VERBOSE]', action='count', default=(os.getenv('PW2_VERBOSE', '').count('v')))
    parser.add_argument('--no-anonymous-access', help='If set, login is required to configure monitoring/metrics',
                        action='store_true', default=(os.getenv('PW2_WEBNOANONYMOUS') or False))
    parser.add_argument('--admin-user', help='Username for login',
                        default=(os.getenv('PW2_WEBUSER') or 'admin'))
    parser.add_argument('--admin-password', help='Password for login to read and configure monitoring',
                        default=(os.getenv('PW2_WEBPASSWORD') or 'pgwatch2admin'))
    parser.add_argument('--no-component-logs', help='Don''t expose component logs via the Web UI',
                        action='store_true', default=(str_to_bool_or_fail(os.getenv('PW2_WEBNOCOMPONENTLOGS')) or False))
    parser.add_argument('--no-stats-summary', help='Don''t expose summary metrics and "top queries" on monitored DBs',
                        action='store_true', default=(str_to_bool_or_fail(os.getenv('PW2_WEBNOSTATSSUMMARY')) or False))
    parser.add_argument('--aes-gcm-keyphrase', help='For encrypting password stored to configDB',
                        default=os.getenv('PW2_AES_GCM_KEYPHRASE'))
    parser.add_argument('--aes-gcm-keyphrase-file', help='For encrypting password stored to configDB. Read from a file on startup',
                        default=os.getenv('PW2_AES_GCM_KEYPHRASE_FILE'))
    parser.add_argument('--datastore', help='In which type of database is metric data stored [influx|postgres]. Default: influx',
                        default=(os.getenv('PW2_DATASTORE') or 'influx'))

    # Postgres config DB
    parser.add_argument('-H', '--host', help='Pgwatch2 Config DB host',
                        default=(os.getenv('PW2_PGHOST') or 'localhost'))
    parser.add_argument('-p', '--port', help='Pgwatch2 Config DB port',
                        default=(os.getenv('PW2_PGPORT') or 5432), type=int)
    parser.add_argument('-d', '--database', help='Pgwatch2 Config DB name',
                        default=(os.getenv('PW2_PGDATABASE') or 'pgwatch2'))
    parser.add_argument('-U', '--user', help='Pgwatch2 Config DB username',
                        default=(os.getenv('PW2_PGUSER') or 'pgwatch2'))
    parser.add_argument('--password', help='Pgwatch2 Config DB password',
                        default=(os.getenv('PW2_PGPASSWORD') or ''))
    parser.add_argument('--pg-require-ssl', help='Pgwatch2 Config DB SSL connection only', action='store_true',
                        default=(str_to_bool_or_fail(os.getenv('PW2_PGSSL')) or False))

    # Postgres metrics DB
    parser.add_argument('--pg-metric-store-conn-str', help='PG Metric Store connection string',
                        default=os.getenv('PW2_PG_METRIC_STORE_CONN_STR'))

    # Influx
    parser.add_argument('--influx-host', help='InfluxDB host',
                        default=(os.getenv('PW2_IHOST') or 'localhost'))
    parser.add_argument('--influx-port', help='InfluxDB port',
                        default=(os.getenv('PW2_IPORT') or '8086'))
    parser.add_argument('--influx-user', help='InfluxDB username',
                        default=(os.getenv('PW2_IUSER') or 'root'))
    parser.add_argument('--influx-password', help='InfluxDB password',
                        default=(os.getenv('PW2_IPASSWORD') or 'root'))
    parser.add_argument('--influx-database', help='InfluxDB database',
                        default=(os.getenv('PW2_IDATABASE') or 'pgwatch2'))
    parser.add_argument('--influx-require-ssl', action='store_true',
                        help='Use SSL for InfluxDB', default=(str_to_bool_or_fail(os.getenv('PW2_ISSL')) or False))
    # Grafana
    parser.add_argument(
        '--grafana_baseurl', help='For linking to Grafana "Query details" dashboard', default=(os.getenv('PW2_GRAFANA_BASEURL') or 'http://0.0.0.0:3000'))

    cmd_args = parser.parse_args()

    logging.basicConfig(format='%(asctime)s %(levelname)s %(process)d %(message)s',
                        level=(logging.DEBUG if int(cmd_args.verbose) >= 2 else (logging.INFO if int(cmd_args.verbose) == 1 else logging.ERROR)))
    logging.debug(cmd_args)

    datadb.setConnectionString(
        cmd_args.host, cmd_args.port, cmd_args.database, cmd_args.user, cmd_args.password, cmd_args.pg_require_ssl)
    err = datadb.isDataStoreConnectionOK()
    if err:
        logging.warning("config DB connection test failed: %s", err)

    if cmd_args.datastore == 'postgres':
        if not cmd_args.pg_metric_store_conn_str:
            raise Exception('--pg-metric-store-conn-str needed with --datastore=postgres')
        datadb.setConnectionStringForMetrics(cmd_args.pg_metric_store_conn_str)
        err = datadb.isMetricStoreConnectionOK()
        if err:
            logging.warning("metrics DB connection test failed: %s", err)
    elif cmd_args.datastore == 'influx':
        import influxdb
        pgwatch2_influx.influx_set_connection_params(cmd_args.influx_host, cmd_args.influx_port, cmd_args.influx_user,
                                                     cmd_args.influx_password, cmd_args.influx_database, cmd_args.influx_require_ssl)

    current_dir = os.path.dirname(os.path.abspath(__file__))
    config = {
        'global': {'server.socket_host': cmd_args.socket_host, 'server.socket_port': cmd_args.socket_port},
        '/static': {'tools.staticdir.root': current_dir, 'tools.staticdir.dir': 'static', 'tools.staticdir.on': True, 'tools.sessions.on': False},
        '/': {'tools.sessions.on': True},
    }

    if cmd_args.ssl:
        if not cmd_args.ssl_cert or not cmd_args.ssl_key:
            raise Exception('--ssl-cert and --ssl-cert needed with --ssl!')
        config['global']['server.ssl_module'] = 'builtin'
        config['global']['server.ssl_certificate'] = cmd_args.ssl_cert
        config['global']['server.ssl_private_key'] = cmd_args.ssl_key
        if cmd_args.ssl_certificate_chain:
            config['global']['server.ssl_certificate_chain'] = cmd_args.ssl_certificate_chain

    if cmd_args.aes_gcm_keyphrase_file:
        if os.path.exists(cmd_args.aes_gcm_keyphrase_file):
            cmd_args.aes_gcm_keyphrase = utils.fileContentsToString(cmd_args.aes_gcm_keyphrase_file)
            if cmd_args.aes_gcm_keyphrase:
                logging.info("loaded aes-gcm keyphrase from %s...", cmd_args.aes_gcm_keyphrase_file)
                if cmd_args.aes_gcm_keyphrase[-1] == '\n':
                    logging.warning("removing newline character from keyphrase input string...")
                    cmd_args.aes_gcm_keyphrase = cmd_args.aes_gcm_keyphrase[:-1]
            else:
                logging.warning("specified aes-gcm keyphrase file empty. cannot use encrypted passwords")
        else:
            logging.warning("specified aes-gcm keyphrase file not found, cannot use encrypted passwords")

    cherrypy.quickstart(Root(), config=config)
