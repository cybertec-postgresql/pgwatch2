import glob
import logging
import os
import datadb


SERVICES = {'pgwatch2': {'log_root': '/var/log/supervisor/', 'glob': 'pgwatch2-stderr*'},
            'influxdb': {'log_root': '/var/log/supervisor/', 'glob': 'influxdb-stderr*'},
            'grafana': {'log_root': '/var/log/grafana/', 'glob': 'grafana.log'},
            'postgres': {'log_root': '/var/log/postgresql/', 'glob': 'postgresql-*.csv'},
            'webui': {'log_root': '/var/log/supervisor/', 'glob': 'webpy-stderr*'},
            }


def get_last_log_lines(service='pgwatch2', lines=200):
    if service not in SERVICES:
        raise Exception('service needs to be one of: ' + SERVICES.keys())

    glob_expression = os.path.join(
        SERVICES[service]['log_root'], SERVICES[service]['glob'])
    log_files = glob.glob(glob_expression)
    if not log_files:
        logging.error('no logfile found for glob %s', glob_expression)
        return []
    log_files.sort(key=os.path.getmtime)
    log_file = log_files[-1]
    logging.debug('extracting last %s lines from %s', lines, log_file)
    with open(log_file, 'rb') as f:
        return f.readlines()[-lines:]


def get_all_monitored_dbs():
    sql = """
        select
          *,
          date_trunc('second', md_last_modified_on) as md_last_modified_on,
          md_config::text,
          md_custom_tags::text,
          coalesce(md_include_pattern, '') as md_include_pattern,
          coalesce(md_exclude_pattern, '') as md_exclude_pattern
        from
          pgwatch2.monitored_db
        order by
          md_is_enabled desc, md_id
    """
    return datadb.execute(sql)[0]


def get_active_db_uniques():
    sql = """
        select
          md_unique_name
        from
          pgwatch2.monitored_db
        where
          md_is_enabled
        order by
          1
    """
    ret, err = datadb.execute(sql)
    if ret:
        return [x['md_unique_name'] for x in ret]
    return []


def get_preset_configs():
    sql = """
        select
          pc_name, pc_description, pc_config::text, date_trunc('second', pc_last_modified_on)::text as pc_last_modified_on,
          coalesce((select array_to_string(array_agg(md_unique_name order by md_unique_name), ',')
            from pgwatch2.monitored_db where md_preset_config_name = pc_name and md_is_enabled
            group by md_preset_config_name), '') as active_dbs
        from
          pgwatch2.preset_config
        order by
          pc_name
    """
    return datadb.execute(sql)[0]


def get_active_metrics_with_versions():
    sql = """
        select
          m_name, array_to_string(array_agg(m_pg_version_from order by m_pg_version_from), ',') as versions
        from
          pgwatch2.metric
        where
          m_is_active
        group by
          1
    """
    return datadb.execute(sql)[0]


def get_all_metrics():
    sql = """
        select
          m_id, m_name, m_pg_version_from, m_sql, coalesce(m_comment, '') as m_comment, m_is_active, m_is_helper, 
          date_trunc('second', m_last_modified_on) as m_last_modified_on
        from
          pgwatch2.metric
        order by
          m_is_active desc, m_name
    """
    return datadb.execute(sql)[0]


def cherrypy_checkboxes_to_bool(param_dict, keys):
    """'key': 'on' => 'key': True"""
    for k in keys:
        if k in param_dict:
            if param_dict[k] == 'on':
                param_dict[k] = True
        else:
            param_dict[k] = False


def cherrypy_empty_text_to_nulls(param_dict, keys):
    """'key': '' => 'key': None"""
    for k in keys:
        if k in param_dict and param_dict[k].strip() == '':
            param_dict[k] = None


def update_monitored_db(params):
    ret = []
    sql = """
        with q_old as (
          /* using CTE to be enable detect if connect info is being changed */
          select * from pgwatch2.monitored_db
          where md_id = %(md_id)s
        )
        update
          pgwatch2.monitored_db new
        set
          md_group = %(md_group)s,
          md_hostname = %(md_hostname)s,
          md_port = %(md_port)s,
          md_dbname = %(md_dbname)s,
          md_include_pattern = %(md_include_pattern)s,
          md_exclude_pattern = %(md_exclude_pattern)s,
          md_user = %(md_user)s,
          md_password = case when %(md_password)s = '***' then new.md_password else %(md_password)s end,
          md_is_superuser = %(md_is_superuser)s,
          md_sslmode = %(md_sslmode)s,
          md_dbtype = %(md_dbtype)s,
          md_is_enabled = %(md_is_enabled)s,
          md_preset_config_name = %(md_preset_config_name)s,
          md_config = %(md_config)s,
          md_custom_tags = %(md_custom_tags)s,
          md_statement_timeout_seconds = %(md_statement_timeout_seconds)s,
          md_last_modified_on = now()
        from
          q_old
        where
          new.md_id = %(md_id)s
        returning
          (q_old.md_hostname, q_old.md_port, q_old.md_dbname, q_old.md_user, q_old.md_password, q_old.md_sslmode) is distinct from
            (%(md_hostname)s, %(md_port)s, %(md_dbname)s, %(md_user)s,
            case when %(md_password)s = '***' then q_old.md_password else %(md_password)s end, %(md_sslmode)s
            ) as connection_data_changed,
            case when %(md_password)s = '***' then q_old.md_password else %(md_password)s end as md_password
    """
    cherrypy_checkboxes_to_bool(params, ['md_is_enabled', 'md_sslmode', 'md_is_superuser'])
    cherrypy_empty_text_to_nulls(
        params, ['md_preset_config_name', 'md_config', 'md_custom_tags'])
    data, err = datadb.execute(sql, params)
    if err:
        raise Exception('Failed to update "monitored_db": ' + err)
    ret.append('Updated!')
    if data[0]['connection_data_changed'] or params['md_is_enabled']:  # show warning when changing connect data but cannot connect
        data, err = datadb.executeOnRemoteHost('select 1', params['md_hostname'], params['md_port'], params['md_dbname'],
                                   params['md_user'], data[0]['md_password'], sslmode=params['md_sslmode'], quiet=True)
        if err:
            ret.append('Could not connect to specified host: ' + str(err))

    return ret


def insert_monitored_db(params):
    ret = []
    sql_insert_new_db = """
        insert into
          pgwatch2.monitored_db (md_unique_name, md_hostname, md_port, md_dbname, md_user, md_password, md_is_superuser,
          md_sslmode, md_is_enabled, md_preset_config_name, md_config, md_statement_timeout_seconds, md_dbtype,
          md_include_pattern, md_exclude_pattern, md_custom_tags, md_group)
        values
          (%(md_unique_name)s, %(md_hostname)s, %(md_port)s, %(md_dbname)s, %(md_user)s, %(md_password)s, %(md_is_superuser)s,
          %(md_sslmode)s, %(md_is_enabled)s, %(md_preset_config_name)s, %(md_config)s, %(md_statement_timeout_seconds)s, %(md_dbtype)s,
          %(md_include_pattern)s, %(md_exclude_pattern)s, %(md_custom_tags)s, %(md_group)s)
        returning
          md_id
    """
    sql_active_dbs = "select datname from pg_database where not datistemplate and datallowconn"
    cherrypy_checkboxes_to_bool(params, ['md_is_enabled', 'md_sslmode', 'md_is_superuser'])
    cherrypy_empty_text_to_nulls(
        params, ['md_preset_config_name', 'md_config', 'md_custom_tags'])

    if not params['md_dbname']:     # add all DBs found
        if params['md_dbtype'] == 'postgres':
            # get all active non-template DBs from the entered host
            active_dbs_on_host, err = datadb.executeOnRemoteHost(sql_active_dbs, host=params['md_hostname'], port=params['md_port'],
                                                                 dbname='template1', user=params['md_user'], password=params['md_password'],
                                                                 sslmode=params['md_sslmode'])
            if err:
                raise Exception("Could not read active DBs from specified host!")
            active_dbs_on_host = [x['datname'] for x in active_dbs_on_host]

            # "subtract" DBs that are already monitored
            currently_monitored_dbs, err = datadb.execute("select md_dbname from pgwatch2.monitored_db where "
                                                          " (md_hostname, md_port) = (%(md_hostname)s, %(md_port)s)", params)
            if err:
                raise Exception("Could not read currently active DBs from config DB!")
            currently_monitored_dbs = [x['md_dbname'] for x in currently_monitored_dbs]

            params_copy = params.copy()
            dbs_to_add = set(active_dbs_on_host) - set(currently_monitored_dbs)
            for db_to_add in dbs_to_add:
                params_copy['md_unique_name'] = '{}_{}'.format(params['md_unique_name'], db_to_add)
                params_copy['md_dbname'] = db_to_add
                retdata, err = datadb.execute(sql_insert_new_db, params_copy)
                if err:
                    raise Exception('Failed to insert into "monitored_db": ' + err)
            if currently_monitored_dbs:
                ret.append('Warning! Some DBs not added as already under monitoring: ' + ', '.join(currently_monitored_dbs))
            else:
                ret.append('{} DBs added: {}'.format(len(dbs_to_add), ', '.join(dbs_to_add)))
        elif params['md_dbtype'] == 'pgbouncer':
            # get all configured pgbouncer DBs
            params['md_dbname'] = 'pgbouncer'
            active_dbs_on_host, err = datadb.executeOnRemoteHost("show databases", host=params['md_hostname'], port=params['md_port'],
                                                                 dbname='pgbouncer', user=params['md_user'], password=params['md_password'],
                                                                 sslmode=params['md_sslmode'])
            if err:
                raise Exception("Could not read active DBs from specified host!")
            active_dbs_on_host = [x['name'] for x in active_dbs_on_host]

            # "subtract" DBs that are already monitored
            currently_monitored_dbs, err = datadb.execute("select md_dbname from pgwatch2.monitored_db where "
                                                          " (md_hostname, md_port) = (%(md_hostname)s, %(md_port)s)",
                                                          params)
            if err:
                raise Exception("Could not read currently active DBs from config DB!")
            currently_monitored_dbs = [x['md_dbname'] for x in currently_monitored_dbs]

            params_copy = params.copy()
            dbs_to_add = set(active_dbs_on_host) - set(currently_monitored_dbs)
            for db_to_add in dbs_to_add:
                params_copy['md_unique_name'] = '{}_{}'.format(params['md_unique_name'], db_to_add)
                params_copy['md_dbname'] = db_to_add
                retdata, err = datadb.execute(sql_insert_new_db, params_copy)
                if err:
                    raise Exception('Failed to insert into "monitored_db": ' + err)
            if currently_monitored_dbs:
                ret.append('Warning! Some DBs not added as already under monitoring: ' + ', '.join(currently_monitored_dbs))
            else:
                ret.append('{} DBs added: {}'.format(len(dbs_to_add), ', '.join(dbs_to_add)))
    else:   # only 1 DB
        data, err = datadb.execute(sql_insert_new_db, params)
        if err:
            raise Exception('Failed to insert into "monitored_db": ' + err)
        ret.append('Host with ID {} added!'.format(data[0]['md_id']))
        data, err = datadb.executeOnRemoteHost('select 1', params['md_hostname'], params['md_port'], params['md_dbname'],
                                               params['md_user'], params['md_password'], sslmode=params['md_sslmode'], quiet=True)
        if err:
            ret.append('Could not connect to specified host: ' + str(err))
    return ret


def delete_monitored_db(params):
    # delete in config db
    sql = """
        delete from pgwatch2.monitored_db where md_id = %(md_id)s
    """
    ret, err = datadb.execute(sql, params)
    if err:
        raise Exception('Failed to delete from "monitored_db": ' + err)




def update_preset_config(params):
    sql = """
        update
          pgwatch2.preset_config
        set
          pc_description = %(pc_description)s,
          pc_config = %(pc_config)s,
          pc_last_modified_on = now()
        where
          pc_name = %(pc_name)s
    """
    ret, err = datadb.execute(sql, params)
    if err:
        raise Exception('Failed to update "preset_config": ' + err)


def insert_preset_config(params):
    sql = """
        insert into
          pgwatch2.preset_config (pc_name, pc_description, pc_config)
        values
          (%(pc_name)s, %(pc_description)s, %(pc_config)s)
        returning pc_name
    """
    ret, err = datadb.execute(sql, params)
    if err:
        raise Exception('Failed to insert into "preset_config": ' + err)
    return ret[0]['pc_name']


def delete_preset_config(params):
    sql = """
        delete from pgwatch2.preset_config where pc_name = %(pc_name)s
    """
    ret, err = datadb.execute(sql, params)
    if err:
        raise Exception('Failed to delete from "preset_config": ' + err)


def update_metric(params):
    sql = """
        update
          pgwatch2.metric
        set
          m_name = %(m_name)s,
          m_pg_version_from = %(m_pg_version_from)s,
          m_sql = %(m_sql)s,
          m_comment = %(m_comment)s,
          m_is_active = %(m_is_active)s,
          m_is_helper = %(m_is_helper)s,
          m_last_modified_on = now()
        where
          m_id = %(m_id)s
    """
    cherrypy_checkboxes_to_bool(params, ['m_is_active', 'm_is_helper'])
    ret, err = datadb.execute(sql, params)
    if err:
        raise Exception('Failed to update "metric": ' + err)


def insert_metric(params):
    sql = """
        insert into
          pgwatch2.metric (m_name, m_pg_version_from, m_sql, m_comment, m_is_active, m_is_helper)
        values
          (%(m_name)s, %(m_pg_version_from)s, %(m_sql)s, %(m_comment)s, %(m_is_active)s, %(m_is_helper)s)
        returning m_id
    """
    cherrypy_checkboxes_to_bool(params, ['m_is_active', 'm_is_helper'])
    ret, err = datadb.execute(sql, params)
    if err:
        raise Exception('Failed to insert into "metric": ' + err)
    return ret[0]['m_id']


def delete_metric(params):
    sql = """
        delete from pgwatch2.metric where m_id = %(m_id)s
    """
    ret, err = datadb.execute(sql, params)
    if err:
        raise Exception('Failed to delete from "metric": ' + err)


if __name__ == '__main__':
    # print(get_last_log_lines())
    # print(get_all_monitored_dbs())
    # print(get_preset_configs())
    d = {'cb1': 'on', 't': ''}
    cherrypy_checkboxes_to_bool(d, ['cb2'])
    print(d)
    cherrypy_empty_text_to_nulls(d, ['t'])
    print(d)
