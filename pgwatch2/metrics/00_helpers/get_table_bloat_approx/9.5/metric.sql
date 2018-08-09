BEGIN;

CREATE EXTENSION IF NOT EXISTS pgstattuple WITH SCHEMA PUBLIC;

DO $OUTER$

DECLARE
  l_sproc_text text := $_SQL_$
CREATE OR REPLACE FUNCTION public.get_table_bloat_approx(OUT approx_free_percent double precision, OUT approx_free_space double precision) AS
$$
    select
      avg(approx_free_percent)::double precision as approx_free_percent,
      sum(approx_free_space)::double precision as approx_free_space
    from
      pg_class c
      join
      pg_namespace n on n.oid = c.relnamespace
      join lateral public.pgstattuple_approx(c.oid) on true
    where
      relkind in ('r', 'm')
      and c.relpages >= 128 -- tables >1mb
      and not n.nspname like any (array[E'pg\\_%', 'information_schema'])
      having sum(approx_free_space)::double precision > 0
$$ LANGUAGE sql SECURITY DEFINER;
$_SQL_$;

BEGIN
  IF (regexp_matches(
  		regexp_replace(current_setting('server_version'), '(beta|devel).*', '', 'g'),
        E'\\d+\\.?\\d+?')
      )[1]::double precision > 9.4 THEN
    EXECUTE l_sproc_text;

    EXECUTE 'GRANT EXECUTE ON FUNCTION public.get_table_bloat_approx() TO public;';
    EXECUTE 'COMMENT ON FUNCTION public.get_table_bloat_approx() is ''created for pgwatch2''';
  END IF;
END;
$OUTER$;

COMMIT;
