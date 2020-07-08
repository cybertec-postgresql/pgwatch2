-- DROP FUNCTION IF EXISTS public.ensure_partition_metric(text);
-- select * from public.ensure_partition_metric('wal');

CREATE OR REPLACE FUNCTION admin.ensure_partition_metric(
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
BEGIN

  PERFORM pg_advisory_xact_lock(regexp_replace( md5(metric) , E'\\D', '', 'g')::varchar(10)::int8);

  IF NOT EXISTS (SELECT 1
                   FROM pg_tables
                  WHERE tablename = metric
                    AND schemaname = 'public')
  THEN
    --RAISE NOTICE 'creating partition % ...', metric;
    IF metric ~ 'realtime' THEN
        l_template_table := 'admin.metrics_template_realtime';
        l_unlogged := 'UNLOGGED';
    END IF;
    EXECUTE format($$CREATE %s TABLE IF NOT EXISTS public.%s (LIKE %s INCLUDING INDEXES)$$, l_unlogged, quote_ident(metric), l_template_table);
    EXECUTE format($$COMMENT ON TABLE public.%s IS 'pgwatch2-generated-metric-lvl'$$, quote_ident(metric));
  END IF;

END;
$SQL$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION admin.ensure_partition_metric(text) TO pgwatch2;
