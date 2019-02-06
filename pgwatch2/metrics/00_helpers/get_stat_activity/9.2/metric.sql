CREATE OR REPLACE FUNCTION get_stat_activity() RETURNS SETOF pg_stat_activity AS
$$
  select * from pg_stat_activity where datname = current_database() and pid != pg_backend_pid()
$$ LANGUAGE sql VOLATILE SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_stat_activity() TO pgwatch2;
COMMENT ON FUNCTION get_stat_activity() IS 'created for pgwatch2';
