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
