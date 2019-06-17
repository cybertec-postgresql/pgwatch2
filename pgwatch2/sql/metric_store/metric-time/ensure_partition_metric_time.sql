-- DROP FUNCTION admin.ensure_partition_metric_time(text,timestamp with time zone,integer);
-- select * from admin.ensure_partition_metric_time('wal', now(), 1);

CREATE OR REPLACE FUNCTION admin.ensure_partition_metric_time(
    metric text,
    metric_timestamp timestamptz,
    partitions_to_precreate int default 0,
    OUT part_available_from timestamptz,
    OUT part_available_to timestamptz)
RETURNS record AS
/*
  creates a top level metric table + time partition if not already existing.
  returns partition start/end date
*/
$SQL$
DECLARE
  l_year int;
  l_week int;
  l_part_name text;
  l_part_start date;
  l_part_end date;
  l_sql text;
BEGIN

  IF NOT EXISTS (SELECT 1
                   FROM pg_tables
                  WHERE tablename = metric
                    AND schemaname = 'public')
  THEN
    --RAISE NOTICE 'creating top level metrics partition % ...', metric;   
    l_sql := format($$CREATE TABLE IF NOT EXISTS public.%s (LIKE admin.metrics_template INCLUDING INDEXES) PARTITION BY RANGE (time)$$,
                    quote_ident(metric));
    EXECUTE l_sql;
    EXECUTE format($$COMMENT ON TABLE public.%s IS 'pgwatch2-generated-metric-lvl'$$, quote_ident(metric));
  END IF;
  
  FOR i IN 0..partitions_to_precreate LOOP

  l_year := extract(isoyear from (metric_timestamp + '1week'::interval * i));
  l_week := extract(week from (metric_timestamp + '1week'::interval * i));

  l_part_name := format('%s_y%sw%s', metric, l_year, to_char(l_week, 'fm00' ));
  
  IF i = 0 THEN
      l_part_start := to_date(l_year::text || l_week::text, 'iyyyiw');
      l_part_end := l_part_start + '1week'::interval;
      part_available_from := l_part_start;
      part_available_to := l_part_end;
  ELSE
      l_part_start := l_part_start + '1week'::interval;
      l_part_end := l_part_start + '1week'::interval;
      part_available_to := l_part_end;
  END IF;

  IF NOT EXISTS (SELECT 1
                   FROM pg_tables
                  WHERE tablename = l_part_name
                    AND schemaname = 'subpartitions')
  THEN
    --RAISE NOTICE 'creating sub-partition % ...', l_part_name;
    l_sql := format($$CREATE TABLE IF NOT EXISTS subpartitions.%s PARTITION OF public.%s FOR VALUES FROM ('%s') TO ('%s')$$,
                    quote_ident(l_part_name), quote_ident(metric), l_part_start, l_part_end);
    EXECUTE l_sql;
    EXECUTE format($$COMMENT ON TABLE subpartitions.%s IS 'pgwatch2-generated-metric-time-lvl'$$, quote_ident(l_part_name));
  END IF;

  END LOOP;

  
END;
$SQL$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION admin.ensure_partition_metric_time(text,timestamp with time zone,integer) TO pgwatch2;
