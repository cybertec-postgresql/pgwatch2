CREATE OR REPLACE FUNCTION get_wal_size() RETURNS int8 AS
$$
select sum((pg_stat_file('pg_xlog/'||f)).size)::int8 from (select pg_ls_dir('pg_xlog') f) ls
$$ LANGUAGE sql VOLATILE SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_wal_size() TO pgwatch2;
COMMENT ON FUNCTION get_wal_size() IS 'created for pgwatch2';
