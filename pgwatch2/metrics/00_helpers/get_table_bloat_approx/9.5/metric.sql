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

-- below routine fixes function search_path to only include "more secure" schemas with no "public" CREATE privileges
DO $SQL$
    DECLARE
        l_secure_schemas_from_search_path text;
    BEGIN
        SELECT string_agg(safe_sp, ', ' ORDER BY rank) INTO l_secure_schemas_from_search_path FROM (
           SELECT quote_ident(nspname) AS safe_sp, rank
           FROM unnest(regexp_split_to_array(current_setting('search_path'), ',')) WITH ORDINALITY AS csp(schema_name, rank)
                    JOIN pg_namespace n
                         ON quote_ident(n.nspname) = CASE WHEN schema_name = '"$user"' THEN quote_ident(user) ELSE trim(schema_name) END
           WHERE NOT has_schema_privilege('public', n.oid, 'CREATE')
        ) x;

        IF coalesce(l_secure_schemas_from_search_path, '') = '' THEN
            RAISE NOTICE 'search_path = %', current_setting('search_path');
            RAISE EXCEPTION $$get_table_bloat_approx() SECURITY DEFINER helper will not be created as all schemas on search_path are unsecured where all users can create objects -
              execute 'REVOKE CREATE ON SCHEMA public FROM PUBLIC' to tighten security or comment out the DO block to disable the check$$;
        ELSE
            RAISE NOTICE '%', format($$ALTER FUNCTION get_table_bloat_approx() SET search_path TO %s$$, l_secure_schemas_from_search_path);
            EXECUTE format($$ALTER FUNCTION get_table_bloat_approx() SET search_path TO %s$$, l_secure_schemas_from_search_path);
        END IF;
    END;
$SQL$;

COMMIT;
