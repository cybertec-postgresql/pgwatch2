/*
code "borrowed" from https://github.com/zalando/PGObserver/blob/master/sql/data_collection_helpers/get_stat_statements.sql

get_stat_statements() - a security workaround wrapper around pg_stat_statements view

The wrapper is not needed because sadly non-superusers don't even see the pg_stat_statements.queryid column for queries that were not execute by them

Be aware! Includes a security risk - non-superusers with execute grants on the sproc
will be able to see executed utility commands which might include "secret" data (e.g. alter role x with password y)!

Usage not really recommended for servers less than 9.2 (http://wiki.postgresql.org/wiki/What%27s_new_in_PostgreSQL_9.2#pg_stat_statements)
thus the "if" in code
*/


DO $OUTER$
DECLARE
  l_pgver double precision;
  l_sproc_text text := $SQL$
CREATE OR REPLACE FUNCTION get_stat_statements() RETURNS SETOF pg_stat_statements AS
$$
  select s.* from pg_stat_statements s join pg_database d on d.oid = s.dbid and d.datname = current_database()
$$ LANGUAGE sql VOLATILE SECURITY DEFINER;
$SQL$;
  l_sproc_text_queryid text := $SQL$
CREATE OR REPLACE FUNCTION get_stat_statements() RETURNS TABLE (
	queryid int8, query text, calls int8, total_time float8, rows int8, shared_blks_hit int8, shared_blks_read int8,
	shared_blks_dirtied int8, shared_blks_written int8, local_blks_hit int8, local_blks_read int8, local_blks_dirtied int8,
	local_blks_written int8, temp_blks_read int8, temp_blks_written int8, blk_read_time float8, blk_write_time float8,
  userid int8, dbid int8
) AS
$$
begin
  return query
  	select (regexp_replace(md5(s.query), E'\\D', '', 'g'))::varchar(10)::int8 as queryid,
  	s.query, s.calls, s.total_time, s.rows, s.shared_blks_hit, s.shared_blks_read, s.shared_blks_dirtied, s.shared_blks_written,
  	s.local_blks_hit, s.local_blks_read, s.local_blks_dirtied, s.local_blks_written, s.temp_blks_read, s.temp_blks_written,
  	s.blk_read_time, s.blk_write_time, s.userid::int8, s.dbid::int8
  from pg_stat_statements s join pg_database d on d.oid = s.dbid and d.datname = current_database();
  end;
$$ LANGUAGE plpgsql VOLATILE SECURITY DEFINER;
$SQL$;
BEGIN
  SELECT ((regexp_matches(
      regexp_replace(current_setting('server_version'), '(beta|devel).*', '', 'g'),
        E'\\d+\\.?\\d+?'))[1])::double precision INTO l_pgver;
  IF l_pgver > 9.1 THEN   --parameters normalized only from 9.2
      EXECUTE format(CASE WHEN l_pgver > 9.3 THEN l_sproc_text ELSE l_sproc_text_queryid END);
    EXECUTE 'GRANT EXECUTE ON FUNCTION get_stat_statements() TO pgwatch2';
    EXECUTE 'COMMENT ON FUNCTION get_stat_statements() IS ''created for pgwatch2''';
  END IF;
END;
$OUTER$;
