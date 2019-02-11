-- DROP FUNCTION admin.ensure_partition_metric_dbname_time(text,text,timestamp with time zone,integer);
-- select * from admin.ensure_partition_metric_dbname_time('wal', 'kala', now());

CREATE OR REPLACE FUNCTION admin.ensure_partition_metric_dbname_time(
    metric text,
    dbname text,
    metric_timestamp timestamptz,
    partitions_to_precreate int default 0,
    OUT part_available_from timestamptz,
    OUT part_available_to timestamptz)
RETURNS record AS
/*
  creates a top level metric table, a dbname partition and a time partition if not already existing.
  returns time partition start/end date
*/
$SQL$
DECLARE
  l_year int;
  l_month int;
  l_part_name_2nd text;
  l_part_name_3rd text;
  l_part_start date;
  l_part_end date;
  l_sql text;
BEGIN
  
  -- 1. level
  IF NOT EXISTS (SELECT 1
                   FROM pg_tables
                  WHERE tablename = metric
                    AND schemaname = 'public')
  THEN
    --RAISE NOTICE 'creating partition % ...', metric; 
    EXECUTE format($$CREATE TABLE public.%s (LIKE admin.metrics_template INCLUDING INDEXES) PARTITION BY LIST (dbname)$$,
                    quote_ident(metric));
    EXECUTE format($$COMMENT ON TABLE public.%s IS 'pgwatch2-generated-metric-lvl'$$, quote_ident(metric));
  END IF;

  -- 2. level
  l_part_name_2nd := metric || '_' || dbname;
  IF NOT EXISTS (SELECT 1
                   FROM pg_tables
                  WHERE tablename = l_part_name_2nd
                    AND schemaname = 'subpartitions')
  THEN
    --RAISE NOTICE 'creating partition % ...', l_part_name; 
    EXECUTE format($$CREATE TABLE subpartitions.%s PARTITION OF public.%s FOR VALUES IN (%s) PARTITION BY RANGE (time)$$,
                    quote_ident(l_part_name_2nd), quote_ident(metric), quote_literal(dbname));
    EXECUTE format($$COMMENT ON TABLE subpartitions.%s IS 'pgwatch2-generated-metric-dbname-lvl'$$, quote_ident(l_part_name_2nd));
  END IF;

  -- 3. level
  FOR i IN 0..partitions_to_precreate LOOP

  l_year := extract(isoyear from (metric_timestamp + '1month'::interval * i));
  l_month := extract(month from (metric_timestamp + '1month'::interval * i));

  l_part_name_3rd := format('%s_%s_y%sm%s', metric, dbname, l_year, to_char(l_month, 'fm00'));
  
  IF i = 0 THEN
      l_part_start := to_date(l_year::text || l_month::text, 'YYYYMM');
      l_part_end := l_part_start + '1month'::interval;
      part_available_from := l_part_start;
      part_available_to := l_part_end;
  ELSE
      l_part_start := l_part_start + '1month'::interval;
      l_part_end := l_part_start + '1month'::interval;
      part_available_to := l_part_end;
  END IF;


  IF NOT EXISTS (SELECT 1
                   FROM pg_tables
                  WHERE tablename = l_part_name_3rd
                    AND schemaname = 'subpartitions')
  THEN
    --RAISE NOTICE 'creating time sub-partition % ...', l_part_name;
    l_sql := format($$CREATE TABLE subpartitions.%s PARTITION OF subpartitions.%s FOR VALUES FROM ('%s') TO ('%s')$$,
                    quote_ident(l_part_name_3rd), quote_ident(l_part_name_2nd), l_part_start, l_part_end);
    EXECUTE l_sql;
    EXECUTE format($$COMMENT ON TABLE subpartitions.%s IS 'pgwatch2-generated-metric-dbname-time-lvl'$$, quote_ident(l_part_name_3rd));
  END IF;

  END LOOP;

  
END;
$SQL$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION admin.ensure_partition_metric_dbname_time(text,text,timestamp with time zone,integer) TO pgwatch2;
