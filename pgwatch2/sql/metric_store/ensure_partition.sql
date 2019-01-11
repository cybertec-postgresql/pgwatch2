-- DROP FUNCTION IF EXISTS public.ensure_partition_metric(text);
-- select * from public.ensure_partition_metric('wal');

CREATE OR REPLACE FUNCTION public.ensure_partition_metric(
    metric text
)
RETURNS void AS
/*
  creates a top level metric table if not already existing.
  expects the "metrics_template" table to exist.
*/
$SQL$
BEGIN
  
  IF NOT EXISTS (SELECT 1
                   FROM pg_tables
                  WHERE tablename = metric
                    AND schemaname = 'public')
  THEN
    --RAISE NOTICE 'creating partition % ...', metric;
   
    EXECUTE format($$CREATE TABLE public."%s" (LIKE public.metrics_template INCLUDING INDEXES)$$, metric);
  END IF;

END;
$SQL$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION public.ensure_partition_metric(text) TO pgwatch2;
