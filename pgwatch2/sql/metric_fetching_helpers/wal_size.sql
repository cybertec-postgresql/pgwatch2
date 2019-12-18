CREATE OR REPLACE FUNCTION public.get_wal_size() RETURNS int8 AS
$$
select (sum((pg_stat_file('pg_wal/' || name)).size))::int8 from pg_ls_waldir()
$$ LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = pg_catalog,pg_temp;

REVOKE EXECUTE ON FUNCTION public.get_wal_size() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_wal_size() TO pgwatch2;

COMMENT ON FUNCTION public.get_wal_size() IS 'created for pgwatch2';
