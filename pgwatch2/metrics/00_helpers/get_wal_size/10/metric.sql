CREATE OR REPLACE FUNCTION get_wal_size() RETURNS int8 AS
$$
select (sum((pg_stat_file('pg_wal/' || name)).size))::int8 from pg_ls_waldir()
$$ LANGUAGE sql VOLATILE SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_wal_size() TO pgwatch2;
COMMENT ON FUNCTION get_wal_size() IS 'created for pgwatch2';
