CREATE OR REPLACE FUNCTION get_stat_replication() RETURNS SETOF pg_stat_replication AS
$$
  select * from pg_stat_replication
$$ LANGUAGE sql VOLATILE SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_stat_replication() TO pgwatch2;
COMMENT ON FUNCTION get_stat_replication() IS 'created for pgwatch2';
