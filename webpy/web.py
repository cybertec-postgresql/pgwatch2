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
from decorator import decorator
import subprocess

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


def exec_cmd(args):
    p = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return p.stdout.decode('utf-8'), p.stderr.decode('utf-8')


class Root:

    @cherrypy.expose
    def login(self, **params):
        print(params)
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
        raise cherrypy.HTTPRedirect('/index')

    @logged_in
    @cherrypy.expose
    def dbs(self, **params):
        logging.debug(params)
        message = ''
        if params:
            try:
                if params.get('save'):
                    pgwatch2.update_monitored_db(params)
                    message = 'Updated!'
                elif params.get('new'):
                    msg = pgwatch2.insert_monitored_db(params)
                    message = msg
                elif params.get('delete'):
                    pgwatch2.delete_monitored_db(params)
                    message = 'Entry with ID {} ("{}") deleted!'.format(
                        params['md_id'], params['md_unique_name'])
                elif params.get('influx_delete_single'):
                    if not params['influx_single_unique_name']:
                        raise Exception('No "Unique Name" provided!')
                    pgwatch2_influx.delete_influx_data_single(params['influx_single_unique_name'])
                    message = 'InfluxDB data for "{}" deleted!'.format(params['influx_single_unique_name'])
                elif params.get('influx_delete_all'):
                    active_dbs = pgwatch2.get_active_db_uniques()
                    print('active_dbs', active_dbs)
                    deleted_dbnames = pgwatch2_influx.delete_influx_data_all(active_dbs)
                    message = 'InfluxDB data deleted for: {}'.format(','.join(deleted_dbnames))
            except Exception as e:
                message = 'ERROR: ' + str(e)

        data = pgwatch2.get_all_monitored_dbs()
        preset_configs = pgwatch2.get_preset_configs()
        preset_configs_json = json.dumps(
            {c['pc_name']: c['pc_config'] for c in preset_configs})
        metrics_list = pgwatch2.get_active_metrics_with_versions()
        influx_active_dbnames = pgwatch2_influx.get_active_dbnames()

        tmpl = env.get_template('dbs.html')
        return tmpl.render(message=message, data=data, preset_configs=preset_configs, preset_configs_json=preset_configs_json,
                           metrics_list=metrics_list, influx_active_dbnames=influx_active_dbnames)

    @logged_in
    @cherrypy.expose
    def metrics(self, **params):
        logging.debug(params)
        message = ''
        if True:
            try:
                if params.get('save'):
                    pgwatch2.update_preset_config(params)
                    message = 'Config "{}" updated!'.format(params['pc_name'])
                elif params.get('new'):
                    config = pgwatch2.insert_preset_config(params)
                    message = 'Config "{}" added!'.format(config)
                elif params.get('delete'):
                    pgwatch2.delete_preset_config(params)
                    message = 'Config "{}" deleted!'.format(params['pc_name'])
                if params.get('metric_save'):
                    pgwatch2.update_metric(params)
                    message = 'Metric "{}" updated!'.format(params['m_name'])
                elif params.get('metric_new'):
                    id = pgwatch2.insert_metric(params)
                    message = 'Metric with ID "{}" added!'.format(id)
                elif params.get('metric_delete'):
                    pgwatch2.delete_metric(params)
                    message = 'Metric "{}" deleted!'.format(params['m_name'])
            except Exception as e:
                message = 'ERROR: ' + str(e)

        preset_configs = pgwatch2.get_preset_configs()
        metrics_list = pgwatch2.get_active_metrics_with_versions()
        metric_definitions = pgwatch2.get_all_metrics()

        tmpl = env.get_template('metrics.html')
        return tmpl.render(message=message, preset_configs=preset_configs, metrics_list=metrics_list,
                           metric_definitions=metric_definitions)

    @logged_in
    @cherrypy.expose
    def logs(self, service='pgwatch2', lines=200):
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
        logging.debug('params: %s', params)
        page = params.get('page', 'index')
        dbname = params.get('dbname')
        data = []
        sort_column = params.get('sort_column', 'total_time')
        if sort_column not in pgwatch2_influx.STATEMENT_SORT_COLUMNS:
            raise Exception('invalid "sort_column": ' + sort_column)
        utcn = datetime.utcnow()
        start_time = params.get(
            'start_time', (utcn - timedelta(days=1)).isoformat() + 'Z')
        end_time = params.get('end_time', (utcn.isoformat() + 'Z'))

        dbnames = [x['md_unique_name']
                   for x in pgwatch2.get_all_monitored_dbs()]
        if dbname:
            if page == 'index' and dbname:
                data = pgwatch2_influx.get_db_overview(dbname)
            elif page == 'statements' and dbname:
                data = pgwatch2_influx.find_top_growth_statements(dbname,
                                                                  sort_column,
                                                                  start_time,
                                                                  end_time)

        tmpl = env.get_template('index.html')
        return tmpl.render(dbnames=dbnames, dbname=dbname, page=page, data=data, sort_column=sort_column,
                           start_time=start_time, end_time=end_time, grafana_baseurl=cmd_args.grafana_baseurl)


if __name__ == '__main__':
    parser = ArgumentParser(description='pgwatch2 Web UI')
    # Webserver
    parser.add_argument('--socket-host', help='Webserver Listen Address',
                        default=(os.getenv('PW2_WEBHOST') or '0.0.0.0'))
    parser.add_argument('--socket-port', help='Webserver Listen Port',
                        default=(os.getenv('PW2_WEBPORT') or 8080), type=int)
    parser.add_argument('--ssl', help='Enable Webserver SSL (Self-signed Cert)',
                        default=(os.getenv('PW2_WEBSSL') or False))
    parser.add_argument('--ssl-cert', help='Path to SSL certificate',
                        default=(os.getenv('PW2_WEBCERT') or '/pgwatch2/self-signed-ssl.pem'))
    parser.add_argument('--ssl-key', help='Path to SSL private key',
                        default=(os.getenv('PW2_WEBKEY') or '/pgwatch2/self-signed-ssl.key'))
    parser.add_argument('--ssl-certificate-chain', help='Path to certificate chain file',
                        default=(os.getenv('PW2_WEBCERTCHAIN')))

    # PgWatch2
    parser.add_argument(
        '-v', '--verbose', help='Chat level. none(default)|-v|-vv [$VERBOSE=[0|1|2]]', action='count', default=(os.getenv('VERBOSE') or 0))
    parser.add_argument('--no-anonymous-access', help='If set no login required to configure monitoring/metrics',
                        action='store_true', default=(os.getenv('PW2_WEBNOANONYMOUS') or False))
    parser.add_argument('--admin-user', help='Username for login',
                        default=(os.getenv('PW2_WEBUSER') or 'admin'))
    parser.add_argument('--admin-password', help='Password for login to read and configure monitoring',
                        default=(os.getenv('PW2_WEBPASSWORD') or 'pgwatch2admin'))
    # Postgres
    parser.add_argument('-H', '--host', help='Pgwatch2 Config DB host',
                        default=(os.getenv('PW2_PGHOST') or 'localhost'))
    parser.add_argument('-p', '--port', help='Pgwatch2 Config DB port',
                        default=(os.getenv('PW2_PGPORT') or 5432), type=int)
    parser.add_argument('-d', '--database', help='Pgwatch2 Config DB name',
                        default=(os.getenv('PW2_PGDATABASE') or 'pgwatch2'))
    parser.add_argument('-U', '--user', help='Pgwatch2 Config DB username',
                        default=(os.getenv('PW2_PGUSER') or 'pgwatch2'))
    parser.add_argument('--password', help='Pgwatch2 Config DB password',
                        default=(os.getenv('PW2_PGPASSWORD') or 'pgwatch2admin'))
    parser.add_argument('--pg-require-ssl', help='Pgwatch2 Config DB SSL connection only', action='store_true',
                        default=(os.getenv('PW2_PGSSL') or False))    # TODO add check
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
                        help='Use SSL for InfluxDB', default=(os.getenv('PW2_ISSL') or False))
    # Grafana
    parser.add_argument(
        '--grafana_baseurl', help='For linking to Grafana "Query details" dashboard', default=(os.getenv('PW2_GRAFANA_BASEURL') or 'http://0.0.0.0:3000'))

    cmd_args = parser.parse_args()

    logging.basicConfig(format='%(asctime)s %(levelname)s %(process)d %(message)s',
                        level=(logging.DEBUG if int(cmd_args.verbose) >= 2 else (logging.INFO if int(cmd_args.verbose) == 1 else logging.ERROR)))
    logging.debug(cmd_args)

    datadb.setConnectionString(
        cmd_args.host, cmd_args.port, cmd_args.database, cmd_args.user, cmd_args.password)
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

    cherrypy.quickstart(Root(), config=config)
