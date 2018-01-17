import logging
import psycopg2
import psycopg2.extras


connection_string = "host=localhost dbname=pgwatch2 user=postgres password=postgres connect_timeout='3'"


def setConnectionString(conn_string):
    global connection_string
    connection_string = conn_string


def setConnectionString(host, port, dbname, username, password, connect_timeout=10):
    global connection_string
    connection_string = 'host={} port={} dbname={} user={} password={} connect_timeout={}'.format(host, port, dbname,
                                                                                                  username, password,
                                                                                                  connect_timeout)


def getDataConnection(autocommit=True):
    conn = psycopg2.connect(connection_string)
    if autocommit:
        conn.autocommit = True
    return conn


def execute(sql, params=None, statement_timeout=None, quiet=False):
    result = []
    conn = None
    try:
        conn = getDataConnection()
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


def executeOnRemoteHost(sql, host, port, dbname, user, password='', sslmode='prefer', params=None, statement_timeout=None, quiet=False):
    result = []
    conn = None
    try:
        conn = psycopg2.connect(host=host, port=port, dbname=dbname, user=user, password=password, sslmode=sslmode)
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
            logging.exception('failed to execute "{}" on remote host "{}:{}"'.format(sql))
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
    data = []
    try:
        data = execute('select 1 as x')
    except:
        logging.exception('failed to connect to postgres')
    if data:
        return data[0]['x'] == 1
    else:
        return False


if __name__ == '__main__':
    print('execute', execute('select 1 as x'))
    print('executeOnRemoteHost', executeOnRemoteHost('select 1 as x', 'localhost', 5432, 'pgwatch2', 'postgres'))
