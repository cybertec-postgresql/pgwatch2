from datetime import datetime
from datetime import timedelta
try:
    import influxdb
    from influxdb import InfluxDBClient
except:
    print('Could not import InfluxDBClient - expected if using Postgres metric storage')
import logging

STATEMENT_SORT_COLUMNS = ['total_time', 'mean_time', 'calls', 'shared_blks_hit', 'shared_blks_read', 'shared_blks_written',
                          'temp_blks_read', 'temp_blks_written', 'blk_read_time', 'blk_write_time']

influx_connect_params = {
    'host': 'localhost',
    'port': 8086,
    'username': 'root',
    'password': 'root',
    'database': 'pgwatch2',
    'ssl': False,
}


def influx_set_connection_params(host, port, username, password, database, ssl=False):
    influx_connect_params['host'] = host
    influx_connect_params['port'] = port
    influx_connect_params['username'] = username
    influx_connect_params['password'] = password
    influx_connect_params['database'] = database
    influx_connect_params['ssl'] = ssl


def influx_query(influxql, params=None):
    # try:
    # client = InfluxDBClient(INFLUX_HOST, INFLUX_PORT, INFLUX_USERNAME, INFLUX_PASSWORD, INFLUX_DATABASE, INFLUX_SSL)
    client = InfluxDBClient(**influx_connect_params)
    logging.debug("querying InfluxDB: %s", influxql)
    return client.query(influxql, params=params)
    # except Exception as e:
    #     logging.exception('Exception in influx_query:')
    #     return e


def get_active_dbnames():
    try:
        iql = '''SHOW TAG VALUES WITH KEY = "dbname"'''
        res = influx_query(iql)
        dbnames = set()
        for s in res.raw.get('series', []):
            for db in s['values']:
                dbnames.add(db[1])
        return sorted(list(dbnames))
    except (requests.exceptions.ConnectionError, influxdb.exceptions.InfluxDBClientError):
        raise Exception('ERROR getting DB listing from metrics DB: Could not connect to InfluxDB')


def delete_influx_data_single(db_unique):
    """delete all existing influxdb series for a given dbname"""
    # find all measurements
    iql_all_measurements = "show measurements"
    resp = influx_query(iql_all_measurements, {'epoch': 'ms'})
    if resp:
        all_measurements = []
        for m in resp.raw['series'][0]['values']:  # [['measurment1'],[..]]
            all_measurements.append(m[0])
        all_measurements_str = '"' + '","'.join(all_measurements) + '"'     # add double quotes to measurement names
        iql_drop = """drop series from {} where "dbname" = '{}'""".format(all_measurements_str, db_unique)
        logging.debug("dropping Influx series for DB: %s (%s)", db_unique, iql_drop)
        influx_query(iql_drop , {'epoch': 'ms'})


def delete_influx_data_all(db_uniques_active_pg):
    """delete all existing influxdb series that don't match given active dbname-s"""
    influx_dbnames = get_active_dbnames()
    logging.info('found influx metric data for db-s: %s', influx_dbnames)
    dbs_to_drop = set(influx_dbnames) - set(db_uniques_active_pg)
    logging.info('dropping metrics from all series for db-s: %s', dbs_to_drop)
    for dbname in dbs_to_drop:
        delete_influx_data_single(dbname)
    return dbs_to_drop


def series_to_dict(influx_raw_data, tag_name):
    """{'series': [{'values': [[value1, value2, ...]], 'tags': {'tag': 'tag_val'}, 'name': 'series1', 'columns': ['col1', ...]}, ...]
        >>>
        {'tag_val': {'col1': value1, ...}}
        NB! tag_name should be unique in the set for a deterministic result
    """
    ret = {}
    for series in influx_raw_data['series']:
        if tag_name in series.get('tags', {}):
            ret[series.get('tags')[tag_name]] = dict(
                zip(series['columns'], series['values'][0]))
    return ret


def exec_for_time_pairs(isql, dbname, pairs, decimal_digits=2):
    """pairs=[(time_literal_for_where, time_literal_for_group_by), ...]"""
    ret = []
    for where_time, group_by_time in pairs:
        res = influx_query(isql.format(dbname, where_time, group_by_time))
        if not res:
            ret.append('-')
            continue
        sum = 0
        count = 0
        try:
            for values in res.raw['series'][0]['values']:
                sum += values[1]
                count += 1
            ret.append(round(sum / float(count), decimal_digits))
        except:
            logging.exception('skipping un-expected Influx resultset row')
            ret.append('-')
    return ret


def get_db_overview(dbname):
    data = {}
    time_pairs = [('7d', '1d'), ('1d', '1h'), ('1h', '10m')]

    tps = """
        SELECT non_negative_derivative(mean("xact_commit"), 1s) + non_negative_derivative(mean("xact_rollback"), 1s)
            FROM "db_stats" WHERE "dbname" = '{}' AND  time > now() - {} GROUP BY time({}) fill(none)
    """
    data['TPS'] = exec_for_time_pairs(tps, dbname, time_pairs)

    wal = """SELECT derivative(mean("xlog_location_b"), 1h)
        FROM "wal" WHERE "dbname" = '{}' AND time > now() - {} GROUP BY time({}) fill(none)"""
    data['WAL Bytes (1h rate)'] = exec_for_time_pairs(wal, dbname, time_pairs)

    sb_ratio = """
        SELECT (non_negative_derivative(mean("blks_hit")) / (non_negative_derivative(mean("blks_hit")) + non_negative_derivative(mean("blks_read")))) * 100
         FROM "db_stats" WHERE "dbname" = '{}' AND  time > now() - {} GROUP BY time({}) fill(none)
    """
    data['Shared Buffers Hit Ratio'] = exec_for_time_pairs(
        sb_ratio, dbname, time_pairs)

    rb_ratio = """
        SELECT (non_negative_derivative(mean("xact_rollback")) / (non_negative_derivative(mean("xact_rollback")) + non_negative_derivative(mean("xact_commit")))) * 100
         FROM "db_stats" WHERE "dbname" = '{}' AND  time > now() - {} GROUP BY time({}) fill(none)
    """
    data['Rollback Ratio'] = exec_for_time_pairs(rb_ratio, dbname, time_pairs)

    tup_inserted = """
        SELECT non_negative_derivative(mean("tup_inserted"), 1h)
            FROM "db_stats" WHERE "dbname" = '{}' AND  time > now() - {} GROUP BY time({}) fill(none)
    """
    data['Tuples Inserted (1h rate)'] = exec_for_time_pairs(
        tup_inserted, dbname, time_pairs)

    tup_updated = """
        SELECT non_negative_derivative(mean("tup_updated"), 1h)
            FROM "db_stats" WHERE "dbname" = '{}' AND  time > now() - {} GROUP BY time({}) fill(none)
    """
    data['Tuples Updated (1h rate)'] = exec_for_time_pairs(
        tup_updated, dbname, time_pairs)

    tup_deleted = """
        SELECT non_negative_derivative(mean("tup_deleted"), 1h)
            FROM "db_stats" WHERE "dbname" = '{}' AND  time > now() - {} GROUP BY time({}) fill(none)
    """
    data['Tuples Deleted (1h rate)'] = exec_for_time_pairs(
        tup_deleted, dbname, time_pairs)

    size_b = """
        SELECT derivative(mean("size_b"), 1h)
            FROM "db_stats" WHERE "dbname" = '{}' AND  time > now() - {} GROUP BY time({}) fill(none)
    """
    data['DB size change in bytes (1h)'] = exec_for_time_pairs(
        size_b, dbname, time_pairs)

    temp_bytes_1h = """
        SELECT derivative(mean("temp_bytes"), 1h)
            FROM "db_stats" WHERE "dbname" = '{}' AND  time > now() - {} GROUP BY time({}) fill(none)
    """
    data['Temporary Bytes (1h)'] = exec_for_time_pairs(
        temp_bytes_1h, dbname, time_pairs)

    return sorted(data.items(), key=lambda x: x[0])


def get_top_n_tables(dbname, n=3):      # TODO
    data = {}

    # 3 biggest tables by growth
    size_b = """
    SELECT "total_relation_size_b" FROM table_stats WHERE "dbname" = '{}' AND time > now() - 1h  group by "schema", "table_name" order by time desc limit 1
    """
    res = influx_query(size_b.format(dbname))
    sizes = []
    if res.raw:
        print(res.raw)
        for s in res.raw['series']:
            sizes.append((s['tags']['schema'] + '.' + s['tags']
                          ['table_name'], s['values'][0][1]))
    sizes.sort(key=lambda x: x[1], reverse=True)
    data['top_tables_by_size'] = sizes[:3]

    # top 3 by growth
    # top 3 by IUD
    # top rows/scan
    # top sprocs
    return sorted(data.items(), key=lambda x: x[0])


def get_first_values_for_column(measurement, dbname, column, start_time, end_time):
    iql_first_fmt = """select first("{}"), queryid from {} where dbname = '{}' and time > '{}' and time < '{}' group by queryid"""
    iql_first = iql_first_fmt.format(
        column, measurement, dbname, start_time, end_time)
    # print(iql_first)
    data_first = influx_query(iql_first, {'epoch': 'ms'})
    return data_first


def get_last_values_for_column(measurement, dbname, column, start_time, end_time):
    iql_first_fmt = """select last("{}"), queryid from {} where dbname = '{}' and time > '{}' and time < '{}' group by queryid"""
    iql_first = iql_first_fmt.format(
        column, measurement, dbname, start_time, end_time)
    # print(iql_first)
    data_first = influx_query(iql_first, {'epoch': 'ms'})
    return data_first


def get_deltas_by_column(measurement, dbname, column, start_time, end_time):
    first_dict = {}
    deltas = []  # (queryid, "column" derivative for 1h) [non-negative only]

    data_first = get_first_values_for_column(
        measurement, dbname, column, start_time, end_time)
    logging.info("%s rows found for data_first", len(data_first))
    data_last = get_last_values_for_column(
        measurement, dbname, column, start_time, end_time)
    logging.info("%s rows found for data_last", len(data_last))

    if not (data_first and data_last):
        return []

    for f in data_first.raw['series']:
        # [1481646061039, 9.65, '1112409937']
        first_dict[f['tags']['queryid']] = f['values'][0]

    for l in data_last.raw['series']:
        last_val_list = l['values'][0]   # [1481646061039, 9.65, '1112409937']
        q_id = last_val_list[2]
        if q_id in first_dict:
            val_delta = last_val_list[1] - first_dict[q_id][1]
            time_delta_ms = last_val_list[0] - first_dict[q_id][0]
            if val_delta < 0 or time_delta_ms < 0:  # only 1 data point or stats reset
                continue
            deltas.append({'queryid': q_id, 'delta': val_delta})
        else:
            logging.warning('queryid %s not found from first set', q_id)
    return deltas


def get_first_or_last_row_by_ident_ids(measurement, dbname, ident_column, ids, start_time, end_time, direction='asc'):
    iql_query_text = """select * from {} where dbname = '{}' and time > '{}' and time < '{}' and (""".format(
        measurement, dbname, start_time, end_time)
    is_first = True
    for id in ids:
        if is_first:
            iql_query_text += """"{}" = '{}'""".format(ident_column, id)
            is_first = False
        else:
            iql_query_text += """ or "{}" = '{}'""".format(ident_column, id)

    iql_query_text_latest = iql_query_text + \
        ') group by "{}" order by time {} limit 1'.format(
            ident_column, direction)
    # print(iql_query_text_latest)
    return influx_query(iql_query_text_latest)


def find_top_growth_statements(dbname, sort_column, start_time=(datetime.utcnow() - timedelta(days=1)).isoformat() + 'Z',
                               end_time=datetime.utcnow().isoformat() + 'Z', limit=20):
    """start_time/end_time expect UTC date inputs currently!"""
    if sort_column not in STATEMENT_SORT_COLUMNS:
        raise Exception('unknown sort column: ' + sort_column)
    ret = []        # list of dicts with all columns from "stat_statements"

    deltas = []     # [{'queryid': ..., 'delta': ...}]
    if sort_column == 'mean_time':      # special handling. can't use pg_stat_statement.mean_time because it carries history
        total_time_deltas = get_deltas_by_column(
            'stat_statements', dbname, 'total_time', start_time, end_time)
        call_deltas = get_deltas_by_column(
            'stat_statements', dbname, 'calls', start_time, end_time)
        call_deltas_dict = {}
        for c in call_deltas:
            call_deltas_dict[c['queryid']] = c

        for tt in total_time_deltas:
            # if "calls" is same means was not called in the period
            if tt['queryid'] in call_deltas_dict and call_deltas_dict[tt['queryid']]['delta'] > 0:
                deltas.append({'queryid': tt['queryid'],
                               'delta': tt['delta'] / call_deltas_dict[tt['queryid']]['delta']})
    else:
        deltas = get_deltas_by_column(
            'stat_statements', dbname, sort_column, start_time, end_time)

    if not deltas:
        logging.warning(
            'could not find any stat_statement data for period (%s, %s)', start_time, end_time)
        return []

    deltas.sort(key=lambda x: x['delta'], reverse=True)
    top_n = deltas[:limit]

    newest_data = get_first_or_last_row_by_ident_ids('stat_statements', dbname, 'queryid', [
                                                     t['queryid'] for t in top_n], start_time, end_time, 'desc')
    newest_data_dict = series_to_dict(newest_data.raw, 'queryid')

    oldest_data = get_first_or_last_row_by_ident_ids('stat_statements', dbname, 'queryid', [
                                                     t['queryid'] for t in top_n], start_time, end_time, 'asc')
    oldest_data_dict = series_to_dict(oldest_data.raw, 'queryid')

    for q in top_n:
        q_id = q['queryid']
        if q_id in oldest_data_dict and q_id in newest_data_dict:
            d = oldest_data_dict[q_id]
            d['queryid'] = q_id
            # d.pop('mean_time')
            # mean_time requires different handling
            delta_keys = set(STATEMENT_SORT_COLUMNS) - set(['mean_time'])
            for delta_key in delta_keys:
                if delta_key in newest_data_dict[q_id] and delta_key in oldest_data_dict[q_id]:
                    d[delta_key] = round(
                        newest_data_dict[q_id][delta_key] - oldest_data_dict[q_id][delta_key], 3)
            if (newest_data_dict[q_id]['calls'] - oldest_data_dict[q_id]['calls']) > 0:
                d['mean_time'] = round((newest_data_dict[q_id]['total_time'] - oldest_data_dict[q_id]['total_time']) /
                                       (newest_data_dict[q_id]['calls'] - oldest_data_dict[q_id]['calls']), 3)
            else:
                d['mean_time'] = 0
            ret.append(d)

    return sorted(ret, key=lambda x: x[sort_column], reverse=True)


if __name__ == '__main__':
    logging.basicConfig(
        format='%(asctime)s %(levelname)s %(process)d %(message)s', level=logging.DEBUG)

    # print(find_top_growth_statements('calls', '2016-12-13 06:00:00', '2016-12-14'))
    # print(get_active_dbnames())
    print(get_db_overview('test'))
    # data = influx_query('select * from stat_statements where time > now() - 1d group by "queryid" order by time asc limit 1')
    # print(series_to_dict(data.raw, 'queryid'))
    # print(find_top_growth_statements('test', 'mean_time'))
