import logging
import psycopg2
import psycopg2.extras


connection_string = "host=localhost dbname=pgwatch2 user=pgwatch2 password=pgwatch2admin connect_timeout='3'"
connection_string_metrics = "host=localhost dbname=pgwatch2_metrics user=pgwatch2 password=pgwatch2admin connect_timeout='3'"


def setConnectionString(conn_string):
    global connection_string
    connection_string = conn_string


def setConnectionStringForMetrics(conn_string):
    global connection_string_metrics
    connection_string_metrics = conn_string


def setConnectionString(host, port, dbname, username, password, require_ssl=False, connect_timeout=10):
    global connection_string
    connection_string = 'host={} port={} dbname={} user={} password={} connect_timeout={} {}'.format(
        host, port, dbname, username, password, connect_timeout, '' if not require_ssl else 'sslmode=require')


def getConnection(conn_str=None, autocommit=True):
    conn = psycopg2.connect(conn_str if conn_str else connection_string)    # default to configDB
    if autocommit:
        conn.autocommit = True
    return conn


def execute(sql, params=None, statement_timeout=None, quiet=False, conn_str=None, on_metric_store=False):
    result = []
    conn = None
    try:
        conn = getConnection(connection_string_metrics) if on_metric_store else getConnection(conn_str)
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
            logging.exception('failed to execute "{}" on datastore'.format(sql))
            return result, str(e)
        else:
            raise
    finally:
        if conn:
            try:
                conn.close()
            except:
                logging.exception('failed to close connection')
    return result, None


def executeOnRemoteHost(sql, host, port, dbname, user, password='', sslmode='prefer', sslrootcert='', sslcert='', sslkey='', params=None, statement_timeout=None, quiet=False):
    result = []
    conn = None
    try:
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
            logging.exception('failed to execute "{}" on remote host "{}:{}"'.format(sql, host, port))
            return result, str(e)
        else:
            raise
    finally:
        if conn:
            try:
                conn.close()
            except:
                logging.exception('failed to close connection')
    return result, None


def isDataStoreConnectionOK():
    data, err = execute('select 1 as x', quiet=True)
    return err


def isMetricStoreConnectionOK():
    data, err = execute('select 1 as x', quiet=True, conn_str=connection_string_metrics)
    return err


if __name__ == '__main__':
    print('execute', execute('select 1 as x'))
    print('executeOnRemoteHost', executeOnRemoteHost('select 1 as x', 'localhost', 5432, 'postgres', 'pgwatch2', 'pgwatch2admin'))
    print('isMetricStoreConnectionOK', isMetricStoreConnectionOK())

