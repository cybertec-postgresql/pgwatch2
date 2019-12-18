/*
A wrapper around pg_stat_activity to enable session, blocking lock, etc monitoring
by the non-superuser pgwatch2 role.
Assumes a role has been created named pgwatch2
*/

DO $OUTER$
DECLARE
  l_pgver double precision;
  l_sproc_text_pre92 text := $SQL$
CREATE OR REPLACE FUNCTION public.get_stat_activity() RETURNS SETOF pg_stat_activity AS
$$
  select * from pg_stat_activity where datname = current_database() and procpid != pg_backend_pid()
$$ LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = pg_catalog,pg_temp;
$SQL$;
  l_sproc_text_92_plus text := $SQL$
CREATE OR REPLACE FUNCTION public.get_stat_activity() RETURNS SETOF pg_stat_activity AS
$$
  select * from pg_stat_activity where datname = current_database() and pid != pg_backend_pid()
$$ LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = pg_catalog,pg_temp;
$SQL$;
BEGIN
  SELECT ((regexp_matches(
      regexp_replace(current_setting('server_version'), '(beta|devel).*', '', 'g'),
        E'\\d+\\.?\\d+?'))[1])::double precision INTO l_pgver;
  EXECUTE format(CASE WHEN l_pgver > 9.1 THEN l_sproc_text_92_plus ELSE l_sproc_text_pre92 END);
END;
$OUTER$;

REVOKE EXECUTE ON FUNCTION public.get_stat_activity() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_stat_activity() TO pgwatch2;

COMMENT ON FUNCTION public.get_stat_activity() IS 'created for pgwatch2';
