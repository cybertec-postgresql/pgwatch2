CREATE OR REPLACE FUNCTION public.get_stat_replication() RETURNS SETOF pg_stat_replication AS
$$
  select * from pg_stat_replication
$$ LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = pg_catalog,pg_temp;

REVOKE EXECUTE ON FUNCTION public.get_stat_replication() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_stat_replication() TO pgwatch2;

COMMENT ON FUNCTION public.get_stat_replication() IS 'created for pgwatch2';
