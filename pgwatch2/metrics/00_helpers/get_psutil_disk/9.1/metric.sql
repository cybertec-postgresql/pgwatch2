/* Pre-requisites: PL/Pythonu and "psutil" Python package (e.g. pip install psutil) */
CREATE EXTENSION IF NOT EXISTS plpython3u; /* NB! "plpython3u" might need changing to "plpythonu" (Python 2) everywhere for older OS-es */

CREATE OR REPLACE FUNCTION get_psutil_disk(
	OUT dir_or_tablespace text, OUT path text, OUT total float8, OUT used float8, OUT free float8, OUT percent float8
)
 RETURNS SETOF record
 LANGUAGE plpython3u
 SECURITY DEFINER
AS $FUNCTION$

from os import stat
from os.path import join, exists
from psutil import disk_usage
ret_list = []

# data_directory
r = plpy.execute("select current_setting('data_directory') as dd, current_setting('log_directory') as ld, current_setting('server_version_num')::int as pgver")
dd = r[0]['dd']
ld = r[0]['ld']
du_dd = disk_usage(dd)
ret_list.append(['data_directory', dd, du_dd.total, du_dd.used, du_dd.free, du_dd.percent])

dd_stat = stat(dd)
# log_directory
if ld:
    if not ld.startswith('/'):
        ld_path = join(dd, ld)
    else:
        ld_path = ld
    if exists(ld_path):
        log_stat = stat(ld_path)
        if log_stat.st_dev == dd_stat.st_dev:
            pass                                # no new info, same device
        else:
            du = disk_usage(ld_path)
            ret_list.append(['log_directory', ld_path, du.total, du.used, du.free, du.percent])

# WAL / XLOG directory
# plpy.notice('pg_wal' if r[0]['pgver'] >= 100000 else 'pg_xlog', r[0]['pgver'])
joined_path_wal = join(r[0]['dd'], 'pg_wal' if r[0]['pgver'] >= 100000 else 'pg_xlog')
wal_stat = stat(joined_path_wal)
if wal_stat.st_dev == dd_stat.st_dev:
    pass                                # no new info, same device
else:
    du = disk_usage(joined_path_wal)
    ret_list.append(['pg_wal', joined_path_wal, du.total, du.used, du.free, du.percent])

# add user created tablespaces if any
sql_tablespaces = """
    select spcname as name, pg_catalog.pg_tablespace_location(oid) as location
    from pg_catalog.pg_tablespace where not spcname like any(array[E'pg\\_%'])"""
for row in plpy.cursor(sql_tablespaces):
    du = disk_usage(row['location'])
    ret_list.append([row['name'], row['location'], du.total, du.used, du.free, du.percent])
return ret_list

$FUNCTION$;

GRANT EXECUTE ON FUNCTION get_psutil_disk() TO pgwatch2;
COMMENT ON FUNCTION get_psutil_disk() IS 'created for pgwatch2';
