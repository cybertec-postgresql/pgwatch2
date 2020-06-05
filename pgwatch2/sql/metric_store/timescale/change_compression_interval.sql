-- DROP FUNCTION IF EXISTS admin.timescale_change_compress_interval(interval);
-- select * from admin.timescale_change_compress_interval('1 day');

CREATE OR REPLACE FUNCTION admin.timescale_change_compress_interval(
    new_interval interval
)
RETURNS void AS
/*
  changes all existing tables and writes the new default also into the admin.config table
  so that future new metric hypertables would also automatically use it
*/
$SQL$
DECLARE
    r record;
BEGIN

  INSERT INTO admin.config
  SELECT 'timescale_compress_interval', new_interval::text
  ON CONFLICT (key) DO UPDATE
    SET value = new_interval::text;

  FOR r IN (SELECT quote_ident(table_name) as metric
                   FROM _timescaledb_catalog.hypertable
                  WHERE schema_name = 'public')
  LOOP
    -- RAISE NOTICE 'setting % to %s ...', r.metric, new_interval;
    PERFORM set_chunk_time_interval(r.metric, new_interval);
    PERFORM remove_compress_chunks_policy(format('public.%I', r.metric));
    PERFORM add_compress_chunks_policy(format('public.%I', r.metric), new_interval);
  END LOOP;

END;
$SQL$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION admin.timescale_change_compress_interval(interval) TO pgwatch2;
