BEGIN;

CREATE EXTENSION IF NOT EXISTS pgstattuple;

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

DO $SQL$
    DECLARE
        l_actual_schema text;
    BEGIN
        SELECT n.nspname INTO l_actual_schema FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE proname = 'get_table_bloat_approx';
        IF FOUND THEN
            IF has_schema_privilege('public', l_actual_schema, 'CREATE') THEN
                RAISE EXCEPTION $$get_table_bloat_approx() helper should not be created in an unsecured schema where all users can create objects -
                  'REVOKE CREATE ON SCHEMA % FROM public' to tighten security or comment out the DO block to disable the check$$, l_actual_schema;
            END IF;

            RAISE NOTICE '%', format($$ALTER FUNCTION get_table_bloat_approx() SET search_path TO %s$$, l_actual_schema);
            EXECUTE format($$ALTER FUNCTION get_table_bloat_approx() SET search_path TO %s$$, l_actual_schema);
        END IF;
    END
$SQL$;

COMMIT;
