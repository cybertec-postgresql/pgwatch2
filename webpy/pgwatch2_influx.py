from datetime import datetime
from datetime import timedelta
from influxdb import InfluxDBClient
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
    iql = '''SHOW TAG VALUES WITH KEY = "dbname"'''
    res = influx_query(iql)
    dbnames = []
    for r in res.raw.get('series', []):
        dbnames.append(r['values'][0][1])
    return sorted(dbnames)


def series_to_dict(influx_raw_data, tag_name):
    """{'series': [{'values': [[value1, value2, ...]], 'tags': {'tag': 'tag_val'}, 'name': 'series1', 'columns': ['col1', ...]}, ...]
        >>>
        {'tag_val': {'col1': value1, ...}}
        NB! tag_name should be unique in the set for a deterministic result
    """
    ret = {}
    for series in influx_raw_data['series']:
        if tag_name in series.get('tags', {}):
            ret[series.get('tags')[tag_name]] = dict(zip(series['columns'], series['values'][0]))
    return ret


def get_db_overview(dbname, last_hours=1):
    data = {}

    iql_tps = """
        SELECT non_negative_derivative(mean("xact_commit"), 1s) + non_negative_derivative(mean("xact_rollback"), 1s)
         FROM "db_stats" WHERE "dbname" = '{}' AND  time > now() - {}h GROUP BY time({}h) fill(none)
    """
    res = influx_query(iql_tps.format(dbname, last_hours*2, last_hours))
    if res.raw:
        # print(res.raw['series'][0])
        data['tps'] = round(res.raw['series'][0]['values'][-1][1], 2)

    iql_wal = """SELECT derivative(mean("xlog_location_b"), 1h) FROM "wal" WHERE "dbname" = '{}' AND time > now() - {}h GROUP BY time({}h) fill(none)"""
    res = influx_query(iql_wal.format(dbname, last_hours*2,last_hours))
    if res.raw:
        # print(res.raw)
        data['wal_bytes'] = round(res.raw['series'][0]['values'][-1][1])

    iql_wal = """SELECT derivative(mean("xlog_location_b"), 1h) FROM "wal" WHERE "dbname" = '{}' AND time > now() - {}h GROUP BY time({}h) fill(none)"""
    res = influx_query(iql_wal.format(dbname, last_hours*2,last_hours))
    if res.raw:
        # print(res.raw)
        data['wal_bytes'] = round(res.raw['series'][0]['values'][-1][1])

    iql_sb_ratio = """
        SELECT (non_negative_derivative(mean("blks_hit")) / (non_negative_derivative(mean("blks_hit")) + non_negative_derivative(mean("blks_read")))) * 100
         FROM "db_stats" WHERE "dbname" = '{}' AND  time > now() - {}h GROUP BY time({}h) fill(none)
    """
    res = influx_query(iql_sb_ratio.format(dbname, last_hours*2, last_hours))
    if res.raw:
        # print(res.raw['series'][0])
        data['sb_ratio'] = round(res.raw['series'][0]['values'][-1][1], 2)

    iql_sb_ratio = """
        SELECT (non_negative_derivative(mean("xact_rollback")) / (non_negative_derivative(mean("xact_rollback")) + non_negative_derivative(mean("xact_commit")))) * 100
         FROM "db_stats" WHERE "dbname" = '{}' AND  time > now() - {}h GROUP BY time({}h) fill(none)
    """
    res = influx_query(iql_sb_ratio.format(dbname, last_hours*2, last_hours))
    if res.raw:
        # print(res.raw['series'][0])
        data['rollback_ratio'] = round(res.raw['series'][0]['values'][-1][1], 2)

    tup_inserted = """
    SELECT non_negative_derivative(mean("tup_inserted"), 1h) FROM "db_stats" WHERE "dbname" = '{}' AND  time > now() - {}h GROUP BY time({}h) fill(none)
    """
    res = influx_query(tup_inserted.format(dbname, last_hours*2, last_hours))
    if res.raw:
        data['tup_inserted'] = round(res.raw['series'][0]['values'][-1][1], 2)

    tup_updated = """
    SELECT non_negative_derivative(mean("tup_updated"), 1h) FROM "db_stats" WHERE "dbname" = '{}' AND  time > now() - {}h GROUP BY time({}h) fill(none)
    """
    res = influx_query(tup_updated.format(dbname, last_hours*2, last_hours))
    if res.raw:
        data['tup_updated'] = round(res.raw['series'][0]['values'][-1][1], 2)

    tup_deleted = """
    SELECT non_negative_derivative(mean("tup_deleted"), 1h) FROM "db_stats" WHERE "dbname" = '{}' AND  time > now() - {}h GROUP BY time({}h) fill(none)
    """
    res = influx_query(tup_deleted.format(dbname, last_hours*2, last_hours))
    if res.raw:
        data['tup_deleted'] = round(res.raw['series'][0]['values'][-1][1], 2)

    size_b = """
    SELECT last("size_b"), last("size_b") - first("size_b") as diff FROM "db_stats" WHERE "dbname" = '{}' AND time > now() - 7d
    """
    res = influx_query(size_b.format(dbname))
    if res.raw:
        data['db_size_b'] = round(res.raw['series'][0]['values'][0][1], 2)
        data['db_growth_1w_b'] = round(res.raw['series'][0]['values'][0][2], 2)

    # 3 biggest tables by growth
    size_b = """
    SELECT "total_relation_size_b" FROM table_stats WHERE "dbname" = '{}' AND time > now() - 1h  group by "schema", "table_name" order by time desc limit 1
    """
    res = influx_query(size_b.format(dbname))
    sizes = []
    if res.raw:
        print(res.raw)
        for s in res.raw['series']:
            sizes.append((s['tags']['schema'] + '.' + s['tags']['table_name'], s['values'][0][1]))
    sizes.sort(key=lambda x:x[1], reverse=True)
    data['top_tables_by_size'] = sizes[:3]

    # top 3 by growth
    # top 3 by IUD
    # top rows/scan
    # top sprocs
    # temp bytes
    # avg. backends

    return data


# def find_top_growth_series(measurement, column, start_time, end_time, tags=None):
def find_top_growth_statements(column, start_time, end_time=''):
    first = {}
    non_negative_derivative = []  # (queryid, "column" derivative for 1h) [non-negative only]
    iql_first = "select first({}), queryid from stat_statements where time > '{}' {} group by queryid"
    iql_last = "select last({}), queryid from stat_statements where time > '{}' {} group by queryid"   # join to a single query?
    if end_time:
        end_time = "and time < '{}'".format(end_time)
    data_first = influx_query(iql_first.format(column, start_time, end_time), {'epoch': 'ms'})
    data_last = influx_query(iql_last.format(column, start_time, end_time), {'epoch': 'ms'})

    for f in data_first.raw['series']:
        # print(f)
        first[f['tags']['queryid']] = f['values'][0]    # [1481646061039, 9.65, '1112409937']

    for l in data_last.raw['series']:
        last_val = l['values'][0]   # [1481646061039, 9.65, '1112409937']
        q_id = last_val[2]
        if q_id in first:
            val_delta = last_val[1] - first[q_id][1]
            if val_delta <= 0:
                continue
            time_delta_ms = last_val[0] - first[q_id][0]
            non_negative_derivative.append((q_id, (val_delta / time_delta_ms * 1000.0 * 3600)))    # ms/s
        else:
            print(q_id, 'not found from first')
    # print(data_last)
    if not non_negative_derivative:
        return []

    non_negative_derivative.sort(key=lambda x: x[1], reverse=True)
    top_n = non_negative_derivative[:20]
    iql_query_text = 'select "queryid", first("query") from stat_statements where time > \'{}\' {} and ('.format(start_time, end_time)
    is_first = True
    for q in top_n:
        if is_first:
            iql_query_text += '"queryid" = \'{}\''.format(q[0])
            is_first = False
        else:
            iql_query_text += ' or "queryid" = \'{}\''.format(q[0])

    iql_query_text += ') group by time(30d), "queryid" fill(none)'
    query_texts = influx_query(iql_query_text)
    # print(query_texts.raw)
    for q in query_texts.raw['series']:
        i = 0
        while i < len(top_n):
            if top_n[i][0] == q['values'][0][1]:
                top_n[i] = (top_n[i][0], top_n[i][1], q['values'][0][2])    # (queryid, non_negative_derivative, query)
                break
            i += 1

    return top_n


def get_first_values_for_column(measurement, dbname, column, start_time, end_time):
    iql_first_fmt = """select first("{}"), queryid from {} where dbname = '{}' and time > '{}' and time < '{}' group by queryid"""
    iql_first = iql_first_fmt.format(column, measurement, dbname, start_time, end_time)
    # print(iql_first)
    data_first = influx_query(iql_first, {'epoch': 'ms'})
    return data_first


def get_last_values_for_column(measurement, dbname, column, start_time, end_time):
    iql_first_fmt = """select last("{}"), queryid from {} where dbname = '{}' and time > '{}' and time < '{}' group by queryid"""
    iql_first = iql_first_fmt.format(column, measurement, dbname, start_time, end_time)
    # print(iql_first)
    data_first = influx_query(iql_first, {'epoch': 'ms'})
    return data_first


def get_deltas_by_column(measurement, dbname, column, start_time, end_time):
    first_dict = {}
    deltas = []  # (queryid, "column" derivative for 1h) [non-negative only]

    data_first = get_first_values_for_column(measurement, dbname, column, start_time, end_time)
    logging.info("%s rows found for data_first", len(data_first))
    data_last = get_last_values_for_column(measurement, dbname, column, start_time, end_time)
    logging.info("%s rows found for data_last", len(data_last))

    # print(data_first.raw['series'][0])
    # print(data_last.raw['series'][0])
    if not (data_first and data_last):
        return []

    for f in data_first.raw['series']:
        first_dict[f['tags']['queryid']] = f['values'][0]    # [1481646061039, 9.65, '1112409937']

    for l in data_last.raw['series']:
        last_val_list = l['values'][0]   # [1481646061039, 9.65, '1112409937']
        q_id = last_val_list[2]
        if q_id in first_dict:
            val_delta = last_val_list[1] - first_dict[q_id][1]
            time_delta_ms = last_val_list[0] - first_dict[q_id][0]
            if val_delta < 0 or time_delta_ms < 0:  # only 1 data point or stats reset
                continue
            deltas.append({'queryid': q_id, 'first': first_dict[q_id][1], 'last': last_val_list[1], 'delta': val_delta,
                                             't1': first_dict[q_id][0], 't2': last_val_list[0], 'nnd_h': val_delta / time_delta_ms * 1000.0 * 3600})    # 1/h
        else:
            logging.warning('queryid %s not found from first set', q_id)
    return deltas


def get_first_or_last_row_by_ident_ids(measurement, dbname, ident_column, ids, start_time, end_time, direction='asc'):
    iql_query_text = """select * from {} where dbname = '{}' and time > '{}' and time < '{}' and (""".format(measurement, dbname, start_time, end_time)
    is_first = True
    for id in ids:
        if is_first:
            iql_query_text += """"{}" = '{}'""".format(ident_column, id)
            is_first = False
        else:
            iql_query_text += """ or "{}" = '{}'""".format(ident_column, id)

    iql_query_text_latest = iql_query_text + ') group by "{}" order by time {} limit 1'.format(ident_column, direction)
    # print(iql_query_text_latest)
    return influx_query(iql_query_text_latest)


def find_top_growth_statements(dbname, sort_column, start_time=(datetime.utcnow() - timedelta(days=1)).isoformat() + 'Z',
                               end_time=datetime.utcnow().isoformat()+'Z', limit=50):
    """start_time/end_time expect UTC date inputs currently!"""
    if sort_column not in STATEMENT_SORT_COLUMNS:
        raise Exception('unknown sort column: ' + sort_column)
    ret = []        # list of dicts with all columns from "stat_statements"

    deltas = []     # [{'queryid': ..., 'delta': ...}]
    if sort_column == 'mean_time':      # special handling
        total_time_deltas = get_deltas_by_column('stat_statements', dbname, 'total_time', start_time, end_time)
        call_deltas = get_deltas_by_column('stat_statements', dbname, 'calls', start_time, end_time)
        call_deltas_dict = {}
        for c in call_deltas:
            call_deltas_dict[c['queryid']] = c

        for tt in total_time_deltas:
            if tt['queryid'] in call_deltas_dict and call_deltas_dict[tt['queryid']]['delta'] > 0:    # if "calls" is same means was not called in the period
                deltas.append({'queryid': tt['queryid'], 'first': tt['first'] / call_deltas_dict[tt['queryid']]['first'],
                                         'last': tt['last'] / call_deltas_dict[tt['queryid']]['last'],
                                         'delta': tt['delta'] / call_deltas_dict[tt['queryid']]['delta'],
                                         'nnd_h': tt['delta'] / call_deltas_dict[tt['queryid']]['delta'] * 1000.0 * 3600})
    else:
        deltas = get_deltas_by_column('stat_statements', dbname, sort_column, start_time, end_time)

    if not deltas:
        logging.warning('could not find any stat_statement data for period (%s, %s)', start_time, end_time)
        return []

    deltas.sort(key=lambda x: x['delta'], reverse=True)
    top_n = deltas[:limit]

    newest_data = get_first_or_last_row_by_ident_ids('stat_statements', dbname, 'queryid', [t['queryid'] for t in top_n], start_time, end_time, 'desc')
    newest_data_dict = series_to_dict(newest_data.raw, 'queryid')

    oldest_data = get_first_or_last_row_by_ident_ids('stat_statements', dbname, 'queryid', [t['queryid'] for t in top_n], start_time, end_time, 'asc')
    oldest_data_dict = series_to_dict(oldest_data.raw, 'queryid')

    delta_keys = set(STATEMENT_SORT_COLUMNS) - set(['mean_time'])   # mean_time requires different handling
    for q in top_n:
        q_id = q['queryid']
        if q_id in oldest_data_dict and q_id in newest_data_dict:
            d = oldest_data_dict[q_id]
            d['queryid'] = q_id

            for delta_key in delta_keys:
                if delta_key in newest_data_dict[q_id] and delta_key in oldest_data_dict[q_id]:
                    d[delta_key] = round(newest_data_dict[q_id][delta_key] - oldest_data_dict[q_id][delta_key], 3)
            if newest_data_dict[q_id]['calls'] - oldest_data_dict[q_id]['calls'] > 0:
                d['mean_time'] = round((newest_data_dict[q_id]['total_time'] - oldest_data_dict[q_id]['total_time']) / \
                             (newest_data_dict[q_id]['calls'] - oldest_data_dict[q_id]['calls']), 3)
            else:
                d['mean_time'] = 0
            ret.append(d)
    return ret


if __name__ == '__main__':
    logging.basicConfig(format='%(asctime)s %(levelname)s %(process)d %(message)s', level=logging.DEBUG)

    # print(find_top_growth_statements('calls', '2016-12-13 06:00:00', '2016-12-14'))
    # print(get_active_dbnames())
    # print(get_db_overview('test'))
    # data = influx_query('select * from stat_statements where time > now() - 1d group by "queryid" order by time asc limit 1')
    # print(series_to_dict(data.raw, 'queryid'))
    print (find_top_growth_statements('test', 'shared_blks_read'))
