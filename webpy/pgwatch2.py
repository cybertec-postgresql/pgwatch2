import glob
import logging
import os
import datadb
import crypto
import utils
from datetime import datetime
from datetime import timedelta


SERVICES = {'pgwatch2': {'log_root': '/var/log/supervisor/', 'glob': 'pgwatch2-stderr*'},
            'influxdb': {'log_root': '/var/log/supervisor/', 'glob': 'influxdb-stderr*'},
            'grafana': {'log_root': '/var/log/grafana/', 'glob': 'grafana.log'},
            'postgres': {'log_root': '/var/log/postgresql/', 'glob': 'postgresql-*.csv'},
            'webui': {'log_root': '/var/log/supervisor/', 'glob': 'webpy-stderr*'},
            }

STATEMENT_SORT_COLUMNS = ['total_time', 'mean_time', 'calls', 'shared_blks_hit', 'shared_blks_read', 'shared_blks_written',
                          'temp_blks_read', 'temp_blks_written', 'blk_read_time', 'blk_write_time']


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
          md_config_standby::text,
          md_custom_tags::text,
          md_host_config::text,
          coalesce(md_include_pattern, '') as md_include_pattern,
          coalesce(md_exclude_pattern, '') as md_exclude_pattern
        from
          pgwatch2.monitored_db
        order by
          md_is_enabled desc, md_id
    """
    return datadb.execute(sql)[0]


def get_monitored_db_by_id(id):
    sql = """
        select
          *,
          date_trunc('second', md_last_modified_on) as md_last_modified_on,
          md_config::text,
          md_config_standby::text,
          md_custom_tags::text,
          md_host_config::text,
          coalesce(md_include_pattern, '') as md_include_pattern,
          coalesce(md_exclude_pattern, '') as md_exclude_pattern
        from
          pgwatch2.monitored_db
        where
          md_id = %s
    """
    data, err = datadb.execute(sql, (id,))
    if not data:
        return None
    return data[0]


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
          coalesce((select array_to_string(array_agg(md_unique_name order by md_unique_name), ', ')
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
          m_id, m_name, m_pg_version_from, m_sql, m_sql_su, coalesce(m_comment, '') as m_comment, m_is_active, m_is_helper,
          date_trunc('second', m_last_modified_on::timestamp) as m_last_modified_on, m_master_only, m_standby_only,
          coalesce(m_column_attrs::text, '') as m_column_attrs, coalesce(ma_metric_attrs::text, '') as ma_metric_attrs
        from
          pgwatch2.metric
          left join
          pgwatch2.metric_attribute on (ma_metric_name = m_name)
        order by
          m_is_active desc, m_name, m_pg_version_from
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
        if k in param_dict and type(param_dict[k]) == str and param_dict[k].strip() == '':
            param_dict[k] = None


def update_monitored_db(params, cmd_args=None):
    ret = []
    password_plain = params['md_password']
    old_row_data = get_monitored_db_by_id(params['md_id'])

    if params.get('md_password_type') == 'aes-gcm-256' and old_row_data.get('md_password_type') == 'plain-text':    # NB! when changing this part also review set_bulk_password()
        if not cmd_args.aes_gcm_keyphrase:
            ret.append("FYI - not enabling password encryption as keyphrase/keyfile not specified on UI startup (hint: use the PW2_AES_GCM_KEYPHRASE env. variable or --aes-gcm-keyphrase param)")
            params['md_password_type'] = old_row_data['md_password_type']
            params['md_password'] = '***'
        else:
            if params['md_password'] != '***':
                params['md_password'] = crypto.encrypt(cmd_args.aes_gcm_keyphrase, password_plain)
            else:
                params['md_password'] = crypto.encrypt(cmd_args.aes_gcm_keyphrase, old_row_data.get('md_password'))
    elif params.get('md_password_type') == 'plain-text' and old_row_data.get('md_password_type') == 'aes-gcm-256':
            if not cmd_args.aes_gcm_keyphrase:
                ret.append("FYI - skipping password decryption as keyphrase/keyfile not specified on UI startup (hint: use the PW2_AES_GCM_KEYPHRASE env. variable or --aes-gcm-keyphrase param)")
                params['md_password_type'] = old_row_data['md_password_type']
                params['md_password'] = '***'
            else:
                if params['md_password'] == '***':
                    params['md_password'] = crypto.decrypt(cmd_args.aes_gcm_keyphrase, old_row_data.get('md_password'))

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
          md_password = case when %(md_password)s = '***' and %(md_password_type)s = new.md_password_type then new.md_password else %(md_password)s end,
          md_password_type = %(md_password_type)s,
          md_is_superuser = %(md_is_superuser)s,
          md_sslmode = %(md_sslmode)s,
          md_root_ca_path = %(md_root_ca_path)s,
          md_client_cert_path = %(md_client_cert_path)s,
          md_client_key_path = %(md_client_key_path)s,
          md_dbtype = %(md_dbtype)s,
          md_is_enabled = %(md_is_enabled)s,
          md_preset_config_name = %(md_preset_config_name)s,
          md_preset_config_name_standby = %(md_preset_config_name_standby)s,
          md_config = %(md_config)s,
          md_config_standby = %(md_config_standby)s,
          md_host_config = %(md_host_config)s,
          md_only_if_master = %(md_only_if_master)s,
          md_custom_tags = %(md_custom_tags)s,
          md_statement_timeout_seconds = %(md_statement_timeout_seconds)s,
          md_last_modified_on = now()
        from
          q_old
        where
          new.md_id = %(md_id)s
        returning
          (q_old.md_hostname, q_old.md_port, q_old.md_dbname, q_old.md_user, q_old.md_password,
          q_old.md_sslmode, q_old.md_root_ca_path, q_old.md_client_cert_path, q_old.md_client_key_path) is distinct from
            (%(md_hostname)s, %(md_port)s, %(md_dbname)s, %(md_user)s,
            case when %(md_password)s = '***' then q_old.md_password else %(md_password)s end, %(md_sslmode)s,
            %(md_root_ca_path)s, %(md_client_cert_path)s, %(md_client_key_path)s
            ) as connection_data_changed,
            case when %(md_password)s = '***' and %(md_password_type)s = q_old.md_password_type then q_old.md_password else %(md_password)s end as md_password
    """
    cherrypy_checkboxes_to_bool(params, ['md_is_enabled', 'md_sslmode', 'md_is_superuser', 'md_only_if_master'])
    cherrypy_empty_text_to_nulls(params, ['md_preset_config_name', 'md_config', 'md_config_standby', 'md_preset_config_name_standby', 'md_custom_tags', 'md_host_config'])
    if params['md_dbtype'] == 'postgres-continuous-discovery':
        params['md_dbname'] = ''
    
    data, err = datadb.execute(sql, params)
    if err:
        raise Exception('Failed to update "monitored_db": ' + err)
    ret.append('Updated!')

    if params['md_dbtype'] in ['patroni', 'patroni-continuous-discovery']:
        return ret  # check if DCS is accessible?

    # check connection if connect string changed or inactive host activated
    if data[0]['connection_data_changed'] or (old_row_data and (not old_row_data['md_is_enabled'] and params['md_is_enabled'])):  # show warning when changing connect data but cannot connect
        if params.get('md_password_type') == 'aes-gcm-256' and cmd_args.aes_gcm_keyphrase and data[0]['md_password'] and data[0]['md_password'].find('-') > 0:
            password_plain = crypto.decrypt(cmd_args.aes_gcm_keyphrase, data[0]['md_password'])
        else:
            password_plain = data[0]['md_password']
        data, err = datadb.executeOnRemoteHost('select 1', params['md_hostname'], params['md_port'], 'template1' if params['md_dbtype'] == 'postgres-continuous-discovery' else params['md_dbname'],
                                   params['md_user'], password_plain, sslmode=params['md_sslmode'],
                                   sslrootcert=params['md_root_ca_path'], sslcert=params['md_client_cert_path'],
                                   sslkey=params['md_client_key_path'], quiet=True)
        if err:
            ret.append('Could not connect to specified host (ignore if gatherer daemon runs on another host): ' + str(err))

    return ret


def insert_monitored_db(params, cmd_args=None):
    ret = []
    # to enable adding DBs via POST requests where nonmandatory fields are not specified
    expected_monitored_db_params = [ ('md_port', '5432'), ('md_password', ''),
          ('md_root_ca_path', ''), ('md_client_cert_path', ''), ('md_client_key_path', ''), ('md_config', None), ('md_statement_timeout_seconds', '5'), ('md_dbtype', 'postgres'),
          ('md_only_if_master', False), ( 'md_custom_tags', None), ('md_host_config', None), ('md_include_pattern', ''), ('md_exclude_pattern', ''), ('md_group', 'default'),
          ('md_password_type', 'plain-text'), ('md_sslmode', 'disable'), ('md_config_standby', None), ('md_preset_config_name_standby', None)]
    for p, default in expected_monitored_db_params:
        if not p in params:
            params[p] = default
    sql_insert_new_db = """
        insert into
          pgwatch2.monitored_db (md_unique_name, md_hostname, md_port, md_dbname, md_user, md_password, md_password_type, md_is_superuser,
          md_sslmode, md_root_ca_path,md_client_cert_path, md_client_key_path, md_is_enabled, md_preset_config_name, md_config, md_statement_timeout_seconds, md_dbtype,
          md_include_pattern, md_exclude_pattern, md_custom_tags, md_group, md_host_config, md_only_if_master, md_preset_config_name_standby, md_config_standby)
        values
          (%(md_unique_name)s, %(md_hostname)s, %(md_port)s, %(md_dbname)s, %(md_user)s, %(md_password)s, %(md_password_type)s, %(md_is_superuser)s,
          %(md_sslmode)s, %(md_root_ca_path)s, %(md_client_cert_path)s, %(md_client_key_path)s, %(md_is_enabled)s, %(md_preset_config_name)s, %(md_config)s, %(md_statement_timeout_seconds)s, %(md_dbtype)s,
          %(md_include_pattern)s, %(md_exclude_pattern)s, %(md_custom_tags)s, %(md_group)s, %(md_host_config)s, %(md_only_if_master)s, %(md_preset_config_name_standby)s, %(md_config_standby)s)
        returning
          md_id
    """
    sql_active_dbs = "select datname from pg_database where not datistemplate and datallowconn"
    cherrypy_checkboxes_to_bool(params, ['md_is_enabled', 'md_sslmode', 'md_is_superuser', 'md_only_if_master'])
    cherrypy_empty_text_to_nulls(
        params, ['md_preset_config_name', 'md_config', 'md_config_standby', 'md_preset_config_name_standby', 'md_custom_tags', 'md_host_config'])
    password_plain = params['md_password']
    if password_plain == '***':
        raise Exception("'***' cannot be used as password, denotes unchanged password")

    if params.get('md_password_type') == 'aes-gcm-256':
        if not cmd_args.aes_gcm_keyphrase:
            ret.append("FYI - skipping password encryption as keyphrase/keyfile not specified on UI startup (hint: use the PW2_AES_GCM_KEYPHRASE env. variable or --aes-gcm-keyphrase param)")
            params['md_password_type'] = 'plain-text'
        else:
            params['md_password'] = crypto.encrypt(cmd_args.aes_gcm_keyphrase, password_plain)

    if not params['md_dbname'] and params['md_dbtype'] not in ['postgres-continuous-discovery', 'patroni', 'patroni-continuous-discovery', 'patroni-namespace-discovery']:     # add all DBs found
        if params['md_dbtype'] == 'postgres':
            # get all active non-template DBs from the entered host
            active_dbs_on_host, err = datadb.executeOnRemoteHost(sql_active_dbs, host=params['md_hostname'], port=params['md_port'],
                                                                 dbname='template1', user=params['md_user'], password=password_plain,
                                                                 sslmode=params['md_sslmode'], quiet=True)
            if err:
                active_dbs_on_host, err = datadb.executeOnRemoteHost(sql_active_dbs, host=params['md_hostname'], port=params['md_port'],
                                                                     dbname='postgres', user=params['md_user'], password=password_plain,
                                                                     sslmode=params['md_sslmode'], quiet=True)
                if err:
                    raise Exception("Could not read active DBs from specified host! Make sure 'template1' and/or 'postgres' DB-s are connectable. If not DB auto-discovery cannot be used")
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
                                                                 dbname='pgbouncer', user=params['md_user'], password=password_plain,
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
        if params['md_dbtype'] in ['postgres-continuous-discovery', 'patroni-continuous-discovery']:
            params['md_dbname'] = ''
        data, err = datadb.execute(sql_insert_new_db, params)
        if err:
            raise Exception('Failed to insert into "monitored_db": ' + err)
        ret.append('Host with ID {} added!'.format(data[0]['md_id']))

        if params['md_dbtype'] in ['patroni', 'patroni-continuous-discovery']:
            ret.append('Actual DB hosts will be discovered by the metrics daemon via DCS')  # check if DCS is accessible? would cause more deps...
            return ret

        if params['md_dbtype'] == 'postgres-continuous-discovery':
            params['md_dbname'] = 'template1'
        data, err = datadb.executeOnRemoteHost('select 1', params['md_hostname'], params['md_port'], params['md_dbname'],
                                               params['md_user'], password_plain, sslmode=params['md_sslmode'], quiet=True)
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
    sql_metric = """
        update
          pgwatch2.metric
        set
          m_name = %(m_name)s,
          m_pg_version_from = %(m_pg_version_from)s,
          m_sql = %(m_sql)s,
          m_sql_su = %(m_sql_su)s,
          m_comment = %(m_comment)s,
          m_is_active = %(m_is_active)s,
          m_is_helper = %(m_is_helper)s,
          m_master_only = %(m_master_only)s,
          m_standby_only = %(m_standby_only)s,
          m_column_attrs = %(m_column_attrs)s,
          m_last_modified_on = now()
        where
          m_id = %(m_id)s
    """
    sql_metric_attribute = """
        with q_try_upd as (
            update
              pgwatch2.metric_attribute
            set
              ma_metric_attrs = %(ma_metric_attrs)s,
              ma_last_modified_on = now()
            where
              ma_metric_name = %(m_name)s
            returning *
        )
        insert into pgwatch2.metric_attribute (ma_metric_name, ma_metric_attrs)
        select
          %(m_name)s,
          %(ma_metric_attrs)s
        where
          (select count(*) from q_try_upd) = 0
    """
    cherrypy_checkboxes_to_bool(params, ['m_is_active', 'm_is_helper', 'm_master_only', 'm_standby_only'])
    cherrypy_empty_text_to_nulls(params, ['m_column_attrs'])
    _, err = datadb.execute(sql_metric, params, quiet=True)
    if err:
        raise Exception('Failed to update "metric" table: ' + err)
    if params.get('ma_metric_attrs'):
        _, err = datadb.execute(sql_metric_attribute, params, quiet=True)
        if err:
            return 'Failed to update "metric_attribute": ' + err
    return None


def insert_metric(params):
    msg = ''
    sql = """
        insert into
          pgwatch2.metric (m_name, m_pg_version_from, m_sql, m_sql_su, m_comment, m_is_active, m_is_helper, m_master_only, m_standby_only, m_column_attrs)
        values
          (%(m_name)s, %(m_pg_version_from)s, %(m_sql)s, %(m_sql_su)s, %(m_comment)s, %(m_is_active)s, %(m_is_helper)s, %(m_master_only)s, %(m_standby_only)s, %(m_column_attrs)s)
        returning m_id
    """
    sql_metric_attribute = """
        insert into
          pgwatch2.metric_attribute (ma_metric_name, ma_metric_attrs)
        select
          %(m_name)s, %(ma_metric_attrs)s
    """
    cherrypy_checkboxes_to_bool(params, ['m_is_active', 'm_is_helper', 'm_master_only', 'm_standby_only'])
    cherrypy_empty_text_to_nulls(params, ['m_column_attrs'])
    ret, err = datadb.execute(sql, params, quiet=True)
    if err:
        raise Exception('Failed to insert into "metric": ' + err)
    if params.get('ma_metric_attrs'):
        _, err = datadb.execute(sql_metric_attribute, params, quiet=True)
        if err:
            msg = 'Failed to insert metric attributes into "metric_attribute": ' + err

    return ret[0]['m_id'], msg


def delete_metric(params):
    msg = ''
    sql = """
        delete from pgwatch2.metric where m_id = %(m_id)s
    """
    sql_metric_attribute = """
        delete from pgwatch2.metric_attribute
        where ma_metric_name = %(m_name)s
        and (select count(*) from pgwatch2.metric where m_name = %(m_name)s) = 0
    """

    _, err = datadb.execute(sql, params, quiet=True)
    if err:
        raise Exception('Failed to delete from "metric": ' + err)

    ret, err = datadb.execute(sql_metric_attribute, params, quiet=True)
    if err:
        msg = 'Failed to delete orphaned "metric_attribute" entry: ' + err
    elif ret and len(ret) == 1 and int(ret[0]['rows_affected']) > 0:
        msg = 'Delete also orphaned "metric_attribute" entry'
    return msg


def get_all_dbnames():
    sql = """
    SELECT distinct dbname FROM admin.all_distinct_dbname_metrics ORDER BY 1;
    """
    ret, err = datadb.execute(sql, on_metric_store=True)
    if err:
        raise Exception('Failed to get dbnames listing: ' + err)
    return [x['dbname'] for x in ret]


def delete_postgres_metrics_data_single(dbunique):
    sql = """
        select admin.remove_single_dbname_data(%s)
    """
    ret, err = datadb.execute(sql, (dbunique,), on_metric_store=True)
    if err:
        raise Exception('Failed to delete metrics for "{}":'.format(dbunique) + err)

def get_schema_type():
    sql = """select schema_type from admin.storage_schema_type"""
    ret, err = datadb.execute(sql, on_metric_store=True)
    if err:
        raise Exception('Failed to determine storage schema type:' + err)
    if not ret:
        raise Exception('admin.storage_schema_type needs to have one row in it!')
    return ret[0]["schema_type"]

def get_all_top_level_metric_tables():
    sql = """select table_name from admin.get_top_level_metric_tables()"""
    ret, err = datadb.execute(sql, on_metric_store=True)
    if err:
        raise Exception('Failed to determine storage schema type:' + err)
    return [x["table_name"] for x in ret]

def delete_postgres_metrics_for_all_inactive_hosts(active_dbs):
    sql = """select admin.remove_single_dbname_data(%s)"""
    all = get_all_dbnames()
    to_delete = set(all) - set(active_dbs)

    for dbname_to_delete in to_delete:
        ret, err = datadb.execute(sql, (dbname_to_delete,), on_metric_store=True)
        if err:
            logging.exception('Failed to drop data for: ' + dbname_to_delete)

    return list(to_delete)

def disable_all_dbs():
    sql = """update pgwatch2.monitored_db set md_is_enabled = false, md_last_modified_on = now() where md_is_enabled"""
    ret, _ = datadb.execute(sql)
    if ret and len(ret) == 1:
        return ret[0]['rows_affected']
    return '0'

def enable_all_dbs():
    sql = """update pgwatch2.monitored_db set md_is_enabled = true, md_last_modified_on = now() where not md_is_enabled"""
    ret, _ = datadb.execute(sql)
    if ret and len(ret) == 1:
        return ret[0]['rows_affected']
    return '0'

def set_bulk_config(params):
    sql = """update pgwatch2.monitored_db set md_preset_config_name = %(bulk_preset_config_name)s, md_config = null, md_last_modified_on = now() where md_preset_config_name != %(bulk_preset_config_name)s"""
    ret, _ = datadb.execute(sql, params)
    if ret and len(ret) == 1:
        return ret[0]['rows_affected']
    return '0'

def set_bulk_timeout(params):
    sql = """update pgwatch2.monitored_db set md_statement_timeout_seconds = %(bulk_timeout_seconds)s, md_last_modified_on = now() where md_statement_timeout_seconds != %(bulk_timeout_seconds)s"""
    ret, _ = datadb.execute(sql, params)
    if ret and len(ret) == 1:
        return ret[0]['rows_affected']
    return '0'

def set_bulk_password(params, cmd_args):
    err = ''
    sql = """update pgwatch2.monitored_db set md_password_type = %(bulk_password_type)s,  md_password = %(bulk_password)s, md_last_modified_on = now() where (md_password, md_password_type) is distinct from (%(bulk_password)s, %(bulk_password_type)s)"""

    if params.get('bulk_password_type') == 'aes-gcm-256':    # NB! when changing this part also review insert/update_monitored_db()
        if not cmd_args.aes_gcm_keyphrase:
            return "Password encryption not possible as keyphrase/keyfile not specified on UI startup - use the PW2_AES_GCM_KEYPHRASE env. variable or --aes-gcm-keyphrase/ aes-gcm-keyphrase-file params", 0

        params['bulk_password'] = crypto.encrypt(cmd_args.aes_gcm_keyphrase, params.get('bulk_password'))

    ret, _ = datadb.execute(sql, params)
    if ret and len(ret) == 1:
        return err, ret[0]['rows_affected']
    return err, '0'

def exec_for_time_pairs(sql, dbname, pairs, decimal_digits=2):
    ret = []
    for time_window, agg_interval in pairs:
        data, err = datadb.execute(sql, {'dbname': dbname, 'time_window': time_window, 'agg_interval': agg_interval, 'decimal_digits': decimal_digits}, on_metric_store=True, quiet=True)
        # print(data, err)
        if not err and data:
            ret.append(data[0]['metric'])
    return ret


def get_db_overview(dbname):
    data = {}
    time_pairs = [('7d', '1d'), ('1d', '1h'), ('1h', '10m')]

    tps = """
    select round(avg(avg::numeric), %(decimal_digits)s) as metric from (
    select
      extract(epoch from time)::int8 / extract(epoch from %(agg_interval)s::interval)::int as epoch,
      avg( ((roll-roll_lag) + (comm-comm_lag)) / extract(epoch from (time - time_lag))  )
    from (
      select
          time, lag(time) over w as time_lag,
          (data->>'xact_rollback')::int8 as roll, lag((data->>'xact_rollback')::int8) over w as roll_lag,
          (data->>'xact_commit')::int8 as comm, lag((data->>'xact_commit')::int8) over w as comm_lag
      FROM
          db_stats
      WHERE
        time > now() - %(time_window)s::interval
        AND dbname = %(dbname)s
        window w as (order by time)
    ) x
    WHERE (comm > comm_lag or roll > roll_lag) and time > time_lag
    group by 1
    ) y
    """
    data['TPS'] = exec_for_time_pairs(tps, dbname, time_pairs)

    wal = """
    select round(3600 * avg(avg::numeric), %(decimal_digits)s) as metric from (
    select
      time::int8 / extract(epoch from %(agg_interval)s::interval)::int as epoch,
      avg((wal-wal_lag) / (time-lag_time))
    from (
            select
              (data->>'xlog_location_b')::int8 as wal, lag((data->>'xlog_location_b')::int8) over w as wal_lag,
              extract(epoch from time) as time,
              lag(extract(epoch from time)) over w as lag_time
            from wal
            where
            time > now() - %(time_window)s::interval
            AND dbname = %(dbname)s
            window w as (order by time)
    ) x
    where wal >= wal_lag and time > lag_time
    group by 1
    ) y
    """
    data['WAL Bytes (1h)'] = exec_for_time_pairs(wal, dbname, time_pairs)

    sb_ratio = """
    select round(avg(avg::numeric), %(decimal_digits)s) as metric from (
    select
      extract(epoch from time)::int8 / extract(epoch from %(agg_interval)s::interval)::int as epoch,
      avg((hit-hit_lag)::numeric / ((hit-hit_lag) + (read-read_lag))*100)
    from (
            select
              (data->>'blks_hit')::int8 as hit, lag((data->>'blks_hit')::int8) over w as hit_lag,
              (data->>'blks_read')::int8 as read, lag((data->>'blks_read')::int8) over w as read_lag,
              (data->>'xact_rollback')::int8 as roll, lag((data->>'xact_rollback')::int8) over w as roll_lag,
              (data->>'xact_commit')::int8 as comm, lag((data->>'xact_commit')::int8) over w as comm_lag,
              time
            from db_stats
            where
            time > now() - %(time_window)s::interval
            AND dbname = %(dbname)s
            window w as (order by time)
    ) x
    where hit > hit_lag or read > read_lag
    group by 1
    ) y
    """
    data['Shared Buffers Hit Ratio'] = exec_for_time_pairs(sb_ratio, dbname, time_pairs)

    rollback_ratio = """
    select
      round(avg(100 * (roll-roll_lag)::numeric / ((roll-roll_lag) + (comm-comm_lag))), %(decimal_digits)s) as metric
    from (
      select
          time,
          (data->>'xact_rollback')::int8 as roll, lag((data->>'xact_rollback')::int8) over w as roll_lag,
          (data->>'xact_commit')::int8 as comm, lag((data->>'xact_commit')::int8) over w as comm_lag
      FROM
          db_stats
      WHERE
        time > now() - %(time_window)s::interval
        AND dbname = %(dbname)s
        window w as (order by time)
    ) x
    WHERE comm > comm_lag or roll > roll_lag
    """
    data['Rollback Ratio'] = exec_for_time_pairs(rollback_ratio, dbname, time_pairs)



    tup_inserted = """
    select round(avg(avg::numeric), %(decimal_digits)s) as metric from (
    select
      extract(epoch from time)::int8 / extract(epoch from %(agg_interval)s::interval)::int as epoch,
      avg(3600*((ins-ins_lag) * (extract(epoch from %(agg_interval)s::interval))) / extract(epoch from time - time_lag))
    from (
            select
              (data->>'tup_inserted')::int8 as ins, lag((data->>'tup_inserted')::int8) over w as ins_lag,
              time, lag(time) over w as time_lag
            from db_stats
            where
            time > now() - %(time_window)s::interval
            AND dbname = %(dbname)s
            window w as (order by time)
    ) x
    where ins >= ins_lag /*and upd >= upd_lag and del >= del_lag*/
    group by 1
    ) y
    """
    data['Tuples Inserted (1h rate)'] = exec_for_time_pairs(
        tup_inserted, dbname, time_pairs)


    tup_updated = """
    select round(avg(avg::numeric), %(decimal_digits)s) as metric from (
    select
      extract(epoch from time)::int8 / extract(epoch from %(agg_interval)s::interval)::int as epoch,
      avg(3600*((upd-upd_lag) * (extract(epoch from %(agg_interval)s::interval))) / extract(epoch from time - time_lag))
    from (
            select
              (data->>'tup_updated')::int8 as upd, lag((data->>'tup_updated')::int8) over w as upd_lag,
              time, lag(time) over w as time_lag
            from db_stats
            where
            time > now() - %(time_window)s::interval
            AND dbname = %(dbname)s
            window w as (order by time)
    ) x
    where upd >= upd_lag
    group by 1
    ) y
    """
    data['Tuples Updated (1h rate)'] = exec_for_time_pairs(
        tup_updated, dbname, time_pairs)


    tup_deleted = """
    select round(avg(avg::numeric), %(decimal_digits)s) as metric from (
    select
      extract(epoch from time)::int8 / extract(epoch from %(agg_interval)s::interval)::int as epoch,
      avg(3600*((del-del_lag) * (extract(epoch from %(agg_interval)s::interval))) / extract(epoch from time - time_lag))
    from (
            select
              (data->>'tup_deleted')::int8 as del, lag((data->>'tup_deleted')::int8) over w as del_lag,
              time, lag(time) over w as time_lag
            from db_stats
            where
            time > now() - %(time_window)s::interval
            AND dbname = %(dbname)s
            window w as (order by time)
    ) x
    where del >= del_lag
    group by 1
    ) y
    """
    data['Tuples Deleted (1h rate)'] = exec_for_time_pairs(
        tup_deleted, dbname, time_pairs)

    size_b = """
    select round(avg(avg::numeric), %(decimal_digits)s) as metric from (
        select
          extract(epoch from time)::int8 / extract(epoch from %(agg_interval)s::interval)::int as epoch,
          avg(3600 * (size_b - size_b_lag) / extract(epoch from time - time_lag))
        from (
          select
            time, lag(time) over w as time_lag,
            (data->>'size_b')::int8 as size_b,
            lag((data->>'size_b')::int8) over w as size_b_lag
          from
            db_size
          where
            time > now() - %(time_window)s::interval
            AND dbname = %(dbname)s
          window w as (
             order by time
          )
        ) x
        where size_b >= size_b_lag
        group by 1
    ) y
    """
    data['DB size change in bytes (1h rate)'] = exec_for_time_pairs(
      size_b, dbname, time_pairs)

    temp_bytes_1h = """
    select round(avg(avg::numeric), %(decimal_digits)s) as metric from (
        select
          extract(epoch from time)::int8 / extract(epoch from %(agg_interval)s::interval)::int as epoch,
          avg(3600 * (temp_bytes - temp_bytes_lag) / extract(epoch from time - time_lag))
        from (
          select
            time, lag(time) over w as time_lag,
            (data->>'temp_bytes')::int8 as temp_bytes,
            lag((data->>'temp_bytes')::int8) over w as temp_bytes_lag
          from
            db_stats
          where
            time > now() - %(time_window)s::interval
            AND dbname = %(dbname)s
          window w as (
             order by time
          )
        ) x
        where temp_bytes >= temp_bytes_lag
        group by 1
    ) y
    """
    data['Temporary Bytes (1h rate)'] = exec_for_time_pairs(
       temp_bytes_1h, dbname, time_pairs)

    return sorted(data.items(), key=lambda x: x[0])


def find_top_growth_statements(dbname, sort_column, start_time=(datetime.utcnow() - timedelta(days=1)).isoformat() + 'Z',
                               end_time=datetime.utcnow().isoformat() + 'Z', limit=20):
    """start_time/end_time expect UTC date inputs currently!"""
    if sort_column not in STATEMENT_SORT_COLUMNS:
        raise Exception('unknown sort column: ' + sort_column)
    ret = []        # list of dicts with all columns from "stat_statements"
    sql = r"""
    select
      queryid,
      query,
      round(sum(total_time - total_time_lag)::numeric, 2) as total_time,
      round(avg((total_time - total_time_lag)/(calls - calls_lag))::numeric, 2) as mean_time,
      sum(calls - calls_lag) as calls,
      sum(shared_blks_hit - shared_blks_hit_lag) as shared_blks_hit,
      sum(shared_blks_read - shared_blks_read_lag) as shared_blks_read,
      sum(shared_blks_written - shared_blks_written_lag) as shared_blks_written,
      sum(temp_blks_written - temp_blks_written_lag) as temp_blks_written,
      round(sum(blk_read_time - blk_read_time_lag)::numeric, 2) as blk_read_time,
      round(sum(blk_write_time - blk_write_time_lag)::numeric, 2) as blk_write_time
    from (
      select
        tag_data->>'queryid' as queryid,
        tag_data->>'query' as query,
        (data->>'total_time')::float8 as total_time, lag((data->>'total_time')::float8) over w as total_time_lag,
        (data->>'calls')::float8 as calls, lag((data->>'calls')::float8) over w as calls_lag,
        (data->>'shared_blks_hit')::float8 as shared_blks_hit, lag((data->>'shared_blks_hit')::float8) over w as shared_blks_hit_lag,
        (data->>'shared_blks_read')::float8 as shared_blks_read, lag((data->>'shared_blks_read')::float8) over w as shared_blks_read_lag,
        (data->>'shared_blks_written')::float8 as shared_blks_written, lag((data->>'shared_blks_written')::float8) over w as shared_blks_written_lag,
        (data->>'temp_blks_read')::float8 as temp_blks_read, lag((data->>'temp_blks_read')::float8) over w as temp_blks_read_lag,
        (data->>'temp_blks_written')::float8 as temp_blks_written, lag((data->>'temp_blks_written')::float8) over w as temp_blks_written_lag,
        (data->>'blk_read_time')::float8 as blk_read_time, lag((data->>'blk_read_time')::float8) over w as blk_read_time_lag,
        (data->>'blk_write_time')::float8 as blk_write_time, lag((data->>'blk_write_time')::float8) over w as blk_write_time_lag
      from stat_statements
        where dbname = %(dbname)s
        and time between %(start_time)s and %(end_time)s
        and not tag_data->>'query' ~* E'\\(extract\\(\\$\\d+\\W*from\\W*now\\(\\)\\)\\W?\\*\\W*\\$\\d+\\).*::\\w+\\W+as\\W+epoch_ns\\W*,'
        and not tag_data->>'query' ~* E'/\\*\\W*pgwatch2_generated\\W*\\*/'
      window w as (partition by tag_data->>'queryid' order by time)
    ) x
    where calls > calls_lag
    group by 1, 2
    order by {sort_column} desc
    limit %(limit)s
    """
    data, _ = datadb.execute(sql.format(sort_column=sort_column), {'dbname': dbname, 'start_time': start_time, 'end_time': end_time, 'limit': limit}, on_metric_store=True)
    return data



if __name__ == '__main__':
    # print(get_last_log_lines())
    # print(get_all_monitored_dbs())
    # print(get_preset_configs())
    d = {'cb1': 'on', 't': ''}
    cherrypy_checkboxes_to_bool(d, ['cb2'])
    print(d)
    cherrypy_empty_text_to_nulls(d, ['t'])
    print(d)
