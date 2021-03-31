CREATE OR REPLACE FUNCTION get_sequences() RETURNS SETOF pg_sequences AS
$$
  select * from pg_sequences
$$ LANGUAGE sql VOLATILE SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_sequences() TO pgwatch2;
COMMENT ON FUNCTION get_sequences() IS 'created for pgwatch2';
