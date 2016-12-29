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

import pgwatch2
from jinja2 import Environment, FileSystemLoader

env = Environment(loader=FileSystemLoader(os.path.join(str(Path(__file__).parent), 'templates')))


@decorator
def logged_in(f: callable, *args, **kwargs):
    if not cherrypy.request.app.config['pgwatch2']['anonymous_access'] and not cherrypy.session.get('logged_in'):
        raise cherrypy.HTTPRedirect('/login')
    return f(*args, **kwargs)


class Root:

    @cherrypy.expose
    def login(self, **params):
        message = ''
        submit = params.get('submit', False)
        user = params.get('user', '')
        password = params.get('password', '')

        if cherrypy.request.app.config['pgwatch2']['anonymous_access'] == True:
            raise cherrypy.HTTPRedirect('/index')
        if submit:
            if user and password:
                if user == cherrypy.request.app.config['pgwatch2']['admin_user'] \
                        and password == cherrypy.request.app.config['pgwatch2']['admin_password']:
                    cherrypy.session['logged_in'] = True    # default, in-memory sessions
                    cherrypy.session['login_time'] = time.time()
                    raise cherrypy.HTTPRedirect('/index')
                else:
                    message = 'Wrong username and/or password!'
            else:
                message = 'Username and password needed!'
        tmpl = env.get_template('login.html')
        return tmpl.render(message=message, user=user)

    @cherrypy.expose
    def logout(self, **params):
        if 'logged_in' in cherrypy.session:
            del cherrypy.session['logged_in']
        raise cherrypy.HTTPRedirect('/login')

    @logged_in
    @cherrypy.expose
    def dbs(self, **params):
        print(params)
        message = ''
        if True:
            try:
                if params.get('save'):
                    pgwatch2.update_monitored_db(params)
                    message = 'Updated!'
                elif params.get('new'):
                    id = pgwatch2.insert_monitored_db(params)
                    message = 'New entry with ID {} added!'.format(id)
                elif params.get('delete'):
                    pgwatch2.delete_monitored_db(params)
                    message = 'Entry with ID {} ("{}") deleted!'.format(params['md_id'], params['md_unique_name'])
            except Exception as e:
                message = 'ERROR: ' + str(e)

        data = pgwatch2.get_all_monitored_dbs()
        preset_configs = pgwatch2.get_preset_configs()

        tmpl = env.get_template('dbs.html')
        return tmpl.render(message=message, data=data, preset_configs=preset_configs)

    @logged_in
    @cherrypy.expose
    def metrics(self, **params):
        print(params)
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
            raise Exception('service needs to be one of: ' + str(pgwatch2.SERVICES.keys()))

        log_lines = pgwatch2.get_last_log_lines(service, int(lines))

        cherrypy.response.headers['Content-Type'] = 'text/plain'
        return log_lines

    @cherrypy.expose
    def index(self, **params):
        print(params)
        page = params.get('page', 'index')
        dbname = None
        data = []
        default_sort_column = 'total_runtime'
        dbnames = [x['md_unique_name'] for x in pgwatch2.get_all_monitored_dbs()]
        if 'show' in params and params['dbname']:
            dbname = params['dbname']
            if page == 'index' and dbname:
                data = pgwatch2_influx.get_db_overview(dbname)
            elif page == 'statements' and dbname:
                data = pgwatch2_influx.find_top_growth_statements_all_columns(dbname,
                            params.get('sort_column', default_sort_column),
                            params.get('start_time', (datetime.now() - timedelta(days=2)).strftime('%Y-%m-%d')),
                            params.get('end_time', (datetime.now() + timedelta(days=1)).strftime('%Y-%m-%d')))
        tmpl = env.get_template('index.html')
        return tmpl.render(dbnames=dbnames, dbname=dbname, page=page, data=data, sort_column=default_sort_column)


if __name__ == '__main__':
    parser = ArgumentParser(description='pgwatch2 Web UI')
    parser.add_argument('-c', '--config', help='Config ini file', default='web.conf')
    parser.add_argument('-v', '--verbose', help='Chat level. none(default)|-v|-vv [$VERBOSE=[0|1|2]]', action='count', default=(os.getenv('VERBOSE') or 0))
    # Postgres
    parser.add_argument('-H', '--host', help='Pgwatch2 Config DB host', default='localhost')
    parser.add_argument('-p', '--port', help='Pgwatch2 Config DB port', default=5432, type=int)
    parser.add_argument('-d', '--dbname', help='Pgwatch2 Config DB name', default='pgwatch2')
    parser.add_argument('-U', '--username', help='Pgwatch2 Config DB username', default='postgres')
    parser.add_argument('--password', help='Pgwatch2 Config DB password', default=os.getenv('PGWATCH2_PASSWORD') or 'pgwatch2admin')
    # Influx
    parser.add_argument('--influx-host', help='InfluxDB host', default=os.getenv('PGWATCH2_INFLUX_HOST') or 'localhost')
    parser.add_argument('--influx-port', help='InfluxDB port', default=os.getenv('PGWATCH2_INFLUX_PORT') or '8086')
    parser.add_argument('--influx-username', help='InfluxDB username', default=os.getenv('PGWATCH2_INFLUX_USERNAME') or 'root')
    parser.add_argument('--influx-password', help='InfluxDB password', default=os.getenv('PGWATCH2_INFLUX_PASSWORD') or 'root')
    parser.add_argument('--influx-database', help='InfluxDB database', default=os.getenv('PGWATCH2_INFLUX_DATABASE') or 'pgwatch2')
    parser.add_argument('--influx-ssl', action='store_true', help='Use SSL for InfluxDB', default=os.getenv('PGWATCH2_INFLUX_SSL') or False)

    args = parser.parse_args()
    logging.basicConfig(format='%(asctime)s %(levelname)s %(process)d %(message)s',
                        level=(logging.DEBUG if int(args.verbose) >= 2 else (logging.INFO if int(args.verbose) == 1 else logging.ERROR)))
    logging.debug(args)

    datadb.setConnectionString(args.host, args.port, args.dbname, args.username, args.password)
    pgwatch2_influx.influx_set_connection_params(args.influx_host, args.influx_port, args.influx_username,
                                                           args.influx_password, args.influx_database, args.influx_ssl)

    # cherrypy.config.update('web.conf')
    cherrypy.quickstart(Root(), '/', args.config)
