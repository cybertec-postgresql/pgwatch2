-- DROP FUNCTION IF EXISTS public.ensure_partition_timescale(text);
-- select * from public.ensure_partition_timescale('wal');

CREATE OR REPLACE FUNCTION admin.ensure_partition_timescale(
    metric text
)
RETURNS void AS
/*
  creates a top level metric table if not already existing.
  expects the "metrics_template" table to exist.
*/
$SQL$
DECLARE
    l_template_table text := 'admin.metrics_template';
    l_unlogged text := '';
    --l_compress_chunks_policy text := $$SELECT add_compress_chunks_policy('public.%s', INTERVAL '1 day');$$;
    l_compression_policy text := $$
      ALTER TABLE public.%I SET (
        timescaledb.compress,
        timescaledb.compress_segmentby = 'dbname'
      );
    $$;
BEGIN
  
  IF NOT EXISTS (SELECT *
                   FROM _timescaledb_catalog.hypertable
                  WHERE table_name = metric
                    AND schema_name = 'public')
  THEN
    --RAISE NOTICE 'creating partition % ...', metric;
    IF metric ~ 'realtime' THEN
        l_template_table := 'admin.metrics_template_realtime';
        l_unlogged := 'UNLOGGED';
    END IF;
    EXECUTE format($$CREATE %s TABLE IF NOT EXISTS public.%I (LIKE %s INCLUDING INDEXES)$$, l_unlogged, metric, l_template_table);
    EXECUTE format($$COMMENT ON TABLE public.%I IS 'pgwatch2-generated-metric-lvl'$$, metric);
    PERFORM create_hypertable(format('public.%I', metric), 'time');
    EXECUTE format(l_compression_policy, metric);
    PERFORM add_compress_chunks_policy(format('public.%I', metric), INTERVAL '1 day');

  END IF;

END;
$SQL$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION admin.ensure_partition_timescale(text) TO pgwatch2;
