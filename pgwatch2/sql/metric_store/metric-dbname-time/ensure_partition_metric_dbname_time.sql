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
  l_week int;
  l_part_name_2nd text;
  l_part_name_3rd text;
  l_part_start date;
  l_part_end date;
  l_sql text;
  ideal_length int;
BEGIN
  
  -- 1. level
  IF NOT EXISTS (SELECT 1
                   FROM pg_tables
                  WHERE tablename = metric
                    AND schemaname = 'public')
  THEN
    -- RAISE NOTICE 'creating partition % ...', metric;
    EXECUTE format($$CREATE TABLE IF NOT EXISTS public.%s (LIKE admin.metrics_template INCLUDING INDEXES) PARTITION BY LIST (dbname)$$,
                    quote_ident(metric));
    EXECUTE format($$COMMENT ON TABLE public.%s IS 'pgwatch2-generated-metric-lvl'$$, quote_ident(metric));
  END IF;

  -- 2. level

  l_year := extract(isoyear from (metric_timestamp + '1month'::interval * 1));
  l_week := extract(week from (metric_timestamp + '1week'::interval));
-- raise notice '%_%_y%m%', metric, dbname, l_year, to_char(l_month, 'fm00');
  IF char_length(format('%s_%s_y%sw%s', metric, dbname, l_year, to_char(l_week, 'fm00'))) > 63     -- use "dbname" hash instead of name for overly long ones
  THEN
    ideal_length = 63 - char_length(format('%s__y%sm%s', metric, l_year, to_char(l_week, 'fm00')));
    l_part_name_2nd := metric || '_' || substring(md5(dbname) from 1 for ideal_length);
  ELSE
    l_part_name_2nd := metric || '_' || dbname;
  END IF;

  IF NOT EXISTS (SELECT 1
                   FROM pg_tables
                  WHERE tablename = l_part_name_2nd
                    AND schemaname = 'subpartitions')
  THEN
    --RAISE NOTICE 'creating partition % ...', l_part_name_2nd; 
    EXECUTE format($$CREATE TABLE IF NOT EXISTS subpartitions.%s PARTITION OF public.%s FOR VALUES IN (%s) PARTITION BY RANGE (time)$$,
                    quote_ident(l_part_name_2nd), quote_ident(metric), quote_literal(dbname));
    EXECUTE format($$COMMENT ON TABLE subpartitions.%s IS 'pgwatch2-generated-metric-dbname-lvl'$$, quote_ident(l_part_name_2nd));
  END IF;

  -- 3. level
  FOR i IN 0..partitions_to_precreate LOOP

  l_year := extract(isoyear from (metric_timestamp + '1month'::interval * i));
  l_week := extract(week from (metric_timestamp + '1week'::interval * i));

  l_part_name_3rd := format('%s_y%sw%s', metric, l_year, to_char(l_week, 'fm00' ));

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
                  WHERE tablename = l_part_name_3rd
                    AND schemaname = 'subpartitions')
  THEN
    --RAISE NOTICE 'creating time sub-partition % ...', l_part_name_3rd;
    l_sql := format($$CREATE TABLE IF NOT EXISTS subpartitions.%s PARTITION OF subpartitions.%s FOR VALUES FROM ('%s') TO ('%s')$$,
                    quote_ident(l_part_name_3rd), quote_ident(l_part_name_2nd), l_part_start, l_part_end);
    EXECUTE l_sql;
    EXECUTE format($$COMMENT ON TABLE subpartitions.%s IS 'pgwatch2-generated-metric-dbname-time-lvl'$$, quote_ident(l_part_name_3rd));
  END IF;

  END LOOP;

  
END;
$SQL$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION admin.ensure_partition_metric_dbname_time(text,text,timestamp with time zone,integer) TO pgwatch2;
