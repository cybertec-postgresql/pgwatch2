/* for cases where PL/Python is not an option. not included in preset configs */
BEGIN;

CREATE UNLOGGED TABLE IF NOT EXISTS get_load_average_copy /* remove the UNLOGGED and IF NOT EXISTS part for < v9.1 */
(
    load_1min  float,
    load_5min  float,
    load_15min float,
    proc_count text,
    last_procid int,
    created_on timestamptz not null default now()
);

CREATE OR REPLACE FUNCTION get_load_average_copy(OUT load_1min float, OUT load_5min float, OUT load_15min float) AS
$$
begin
    if random() < 0.02 then    /* clear the table on ca every 50th call not to be bigger than a couple of pages */
        truncate get_load_average_copy;
    end if;
    copy get_load_average_copy (load_1min, load_5min, load_15min, proc_count, last_procid) from '/proc/loadavg' with (format csv, delimiter ' ');
    select t.load_1min, t.load_5min, t.load_15min into load_1min, load_5min, load_15min from get_load_average_copy t order by created_on desc nulls last limit 1;
    return;
end;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_load_average_copy() TO pgwatch2;

COMMENT ON FUNCTION get_load_average_copy() is 'created for pgwatch2';

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
            RAISE EXCEPTION $$get_load_average_copy() SECURITY DEFINER helper will not be created as all schemas on search_path are unsecured where all users can create objects -
              execute 'REVOKE CREATE ON SCHEMA public FROM PUBLIC' to tighten security or comment out the DO block to disable the check$$;
        ELSE
            RAISE NOTICE '%', format($$ALTER FUNCTION get_load_average_copy() SET search_path TO %s$$, l_secure_schemas_from_search_path);
            EXECUTE format($$ALTER FUNCTION get_load_average_copy() SET search_path TO %s$$, l_secure_schemas_from_search_path);
        END IF;
    END;
$SQL$;

COMMIT;
