/*
A privilege escalation wrapper around the pg_stat_statements view.

The wrapper is needed as sadly normal unprivileged users don't even see the pg_stat_statements.queryid column for queries
that were not executed by them.

Be aware! Includes a security risk - non-superusers with execute grants on the sproc will by default be able to see
executed utility commands (set pg_stat_statements.track_utility=off to disable) which might include "secret" data (e.g.
alter role x with password y)!

Usage not recommended for servers less than 9.2 (http://wiki.postgresql.org/wiki/What%27s_new_in_PostgreSQL_9.2#pg_stat_statements).
From v10 the "pg_monitor" system GRANT can be used for the same purpose so the wrapper is not actually needed then.
*/

BEGIN;

CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

CREATE OR REPLACE FUNCTION get_stat_statements() RETURNS SETOF pg_stat_statements AS
$$
  select
    s.*
  from
    pg_stat_statements s
    join
    pg_database d
      on d.oid = s.dbid and d.datname = current_database()
$$ LANGUAGE sql VOLATILE SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_stat_statements() TO pgwatch2;
COMMENT ON FUNCTION get_stat_statements() IS 'created for pgwatch2';

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
            RAISE EXCEPTION $$get_stat_statements() SECURITY DEFINER helper will not be created as all schemas on search_path are unsecured where all users can create objects -
              execute 'REVOKE CREATE ON SCHEMA public FROM PUBLIC' to tighten security or comment out the DO block to disable the check$$;
        ELSE
            RAISE NOTICE '%', format($$ALTER FUNCTION get_stat_statements() SET search_path TO %s$$, l_secure_schemas_from_search_path);
            EXECUTE format($$ALTER FUNCTION get_stat_statements() SET search_path TO %s$$, l_secure_schemas_from_search_path);
        END IF;
    END;
$SQL$;

COMMIT;
