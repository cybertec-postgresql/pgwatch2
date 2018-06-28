
CREATE OR REPLACE FUNCTION public.get_stat_activity() RETURNS SETOF pg_stat_activity AS
$$
  select * from pg_stat_activity where datname = current_database()
$$ LANGUAGE sql VOLATILE SECURITY DEFINER;

REVOKE EXECUTE ON FUNCTION public.get_stat_activity() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_stat_activity() TO pgwatch2;
COMMENT ON FUNCTION public.get_stat_activity() IS 'created for pgwatch2';

