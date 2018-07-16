/* Pre-requisites: PL/Pythonu and "psutil" Python package (e.g. pip install psutil) */

CREATE OR REPLACE FUNCTION public.get_psutil_disk(
	OUT tablespace text, OUT path text, OUT total float8, OUT used float8, OUT free float8, OUT percent float8
)
 RETURNS SETOF record
 LANGUAGE plpythonu
 SECURITY DEFINER
AS $FUNCTION$

from os import stat
from os.path import join
from psutil import disk_usage
ret_list = []

# data_directory
r = plpy.execute("select current_setting('data_directory') as dd, current_setting('log_directory') as ld, current_setting('server_version_num')::int as pgver")
du_dd = disk_usage(r[0]['dd'])
ret_list.append(['data_directory', r[0]['dd'], du_dd.total, du_dd.used, du_dd.free, du_dd.percent])

# log_directory
dd_stat = stat(r[0]['dd'])
joined_path_ld = join(r[0]['dd'], r[0]['ld'])
log_stat = stat(joined_path_ld)
if log_stat.st_dev == dd_stat.st_dev:   # re-use data_directory values if on the same device
    ret_list.append(['log_directory', joined_path_ld, du_dd.total, du_dd.used, du_dd.free, du_dd.percent])
else:
    du = disk_usage(join(r[0]['dd'], r[0]['ld']))
    ret_list.append(['log_directory', joined_path_ld, du.total, du.used, du.free, du.percent])

# WAL / XLOG directory
# plpy.notice('pg_wal' if r[0]['pgver'] >= 100000 else 'pg_xlog', r[0]['pgver'])
joined_path_wal = join(r[0]['dd'], 'pg_wal' if r[0]['pgver'] >= 100000 else 'pg_xlog')
wal_stat = stat(joined_path_wal)
if wal_stat.st_dev == dd_stat.st_dev:   # re-use data_directory values if on the same device
    ret_list.append(['pg_wal', joined_path_wal, du_dd.total, du_dd.used, du_dd.free, du_dd.percent])
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

REVOKE EXECUTE ON FUNCTION public.get_psutil_disk() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_psutil_disk() TO pgwatch2;
COMMENT ON FUNCTION public.get_psutil_disk() IS 'created for pgwatch2';
