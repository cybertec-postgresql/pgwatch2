BEGIN;

CREATE EXTENSION IF NOT EXISTS pgstattuple;

DO $OUTER$

DECLARE
  l_sproc_text text := $_SQL_$
CREATE OR REPLACE FUNCTION get_table_bloat_approx(
  OUT approx_free_percent double precision, OUT approx_free_space double precision,
  OUT dead_tuple_percent double precision, OUT dead_tuple_len double precision) AS
$$
    select
      avg(approx_free_percent)::double precision as approx_free_percent,
      sum(approx_free_space)::double precision as approx_free_space,
      avg(dead_tuple_percent)::double precision as dead_tuple_percent,
      sum(dead_tuple_len)::double precision as dead_tuple_len
    from
      pg_class c
      join
      pg_namespace n on n.oid = c.relnamespace
      join lateral pgstattuple_approx(c.oid) on (c.oid not in (select relation from pg_locks where mode = 'AccessExclusiveLock'))  -- skip locked tables
    where
      relkind in ('r', 'm')
      and c.relpages >= 128 -- tables >1mb
      and not n.nspname like any (array[E'pg\\_%', 'information_schema'])
$$ LANGUAGE sql SECURITY DEFINER;
$_SQL_$;

BEGIN
  IF (regexp_matches(
  		regexp_replace(current_setting('server_version'), '(beta|devel).*', '', 'g'),
        E'\\d+\\.?\\d+?')
      )[1]::double precision > 9.4 THEN
    EXECUTE l_sproc_text;

    EXECUTE 'GRANT EXECUTE ON FUNCTION get_table_bloat_approx() TO pgwatch2;';
    EXECUTE 'COMMENT ON FUNCTION get_table_bloat_approx() is ''created for pgwatch2''';
  END IF;
END;
$OUTER$;

COMMIT;
