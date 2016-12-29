from influxdb import InfluxDBClient
import logging


influx_connect_params = {
    'host': 'localhost',
    'port': 8087,
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


def find_top_growth_statements_all_columns(dbname, column, start_time, end_time=''):
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

    # TODO
    iql_query_text = 'select * from stat_statements where time = \'{}\' {} and ('.format(start_time, end_time)
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


if __name__ == '__main__':
    logging.basicConfig(format='%(asctime)s %(levelname)s %(process)d %(message)s', level=logging.DEBUG)

    # print(find_top_growth_statements('calls', '2016-12-13 06:00:00', '2016-12-14'))
    # print(get_active_dbnames())
    print(get_db_overview('test'))