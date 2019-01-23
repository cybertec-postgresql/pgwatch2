CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

DO $OUTER$
DECLARE
  l_sproc_text text := $_SQL_$
CREATE OR REPLACE FUNCTION get_stat_statements() RETURNS SETOF pg_stat_statements AS
$$
  select s.* from pg_stat_statements s join pg_database d on d.oid = s.dbid and d.datname = current_database()
$$ LANGUAGE sql VOLATILE SECURITY DEFINER;
$_SQL_$;
BEGIN
  IF (regexp_matches(
  		regexp_replace(current_setting('server_version'), '(beta|devel).*', '', 'g'),
        E'\\d+\\.?\\d+?')
      )[1]::double precision > 9.1 THEN   --parameters normalized only from 9.2
    EXECUTE format(l_sproc_text);
    EXECUTE 'GRANT EXECUTE ON FUNCTION get_stat_statements() TO pgwatch2';
    EXECUTE 'COMMENT ON FUNCTION get_stat_statements() IS ''created for pgwatch2''';
  END IF;
END;
$OUTER$;
