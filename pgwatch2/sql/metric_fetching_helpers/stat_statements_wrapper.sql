/*
code "borrowed" from https://github.com/zalando/PGObserver/blob/master/sql/data_collection_helpers/get_stat_statements.sql

public.get_stat_statements() - a security workaround wrapper around pg_stat_statements view

The wrapper is not needed because sadly non-superusers don't even see the pg_stat_statements.queryid column for queries that were not execute by them

Be aware! Includes a security risk - non-superusers with execute grants on the sproc
will be able to see executed utility commands which might include "secret" data (e.g. alter role x with password y)!

Usage not really recommended for servers less than 9.2 (http://wiki.postgresql.org/wiki/What%27s_new_in_PostgreSQL_9.2#pg_stat_statements)
thus the "if" in code
*/


DO $OUTER$
DECLARE
  l_sproc_text text := $SQL$
CREATE OR REPLACE FUNCTION public.get_stat_statements() RETURNS SETOF pg_stat_statements AS
$$
  select s.* from pg_stat_statements s join pg_database d on d.oid = s.dbid and d.datname = current_database()
$$ LANGUAGE sql VOLATILE SECURITY DEFINER;
$SQL$;
BEGIN
  PERFORM 1 from pg_views where viewname = 'pg_stat_statements';
  IF (regexp_matches(
      regexp_replace(current_setting('server_version'), '(beta|devel).*', '', 'g'),
        E'\\d+\\.?\\d+?')
      )[1]::double precision > 9.1 THEN   --parameters normalized only from 9.2
    EXECUTE format(l_sproc_text);
    EXECUTE 'REVOKE EXECUTE ON FUNCTION public.get_stat_statements() FROM PUBLIC;';
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.get_stat_statements() TO pgwatch2';
    EXECUTE 'COMMENT ON FUNCTION public.get_stat_statements() IS ''created for pgwatch2''';
  END IF;
END;
$OUTER$;
