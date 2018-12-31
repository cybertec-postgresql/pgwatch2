-- DROP FUNCTION ensure_partition(text,timestamp with time zone,integer);
-- select * from public.ensure_partition('kala', now(), 1);

CREATE OR REPLACE FUNCTION public.ensure_partition(
    dbname text,
    metric_timestamp timestamptz,
    partitions_to_precreate int default 0,
    OUT part_available_from timestamptz,
    OUT part_available_to timestamptz)
RETURNS record AS
/*
returns partition end date
*/
$SQL$
DECLARE
  l_year int;
  l_week int;
  l_part_name text;
  l_sub_part_name text;
  l_part_start date;
  l_part_end date;
  l_sql text;
BEGIN
  FOR i IN 0..partitions_to_precreate LOOP

  l_year := extract(isoyear from (metric_timestamp + '1week'::interval * i));
  l_week := extract(week from (metric_timestamp + '1week'::interval * i));
  l_part_name := format('metrics_y%sw%s', l_year, l_week);
  
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
                    AND schemaname = 'public')
  THEN
    --RAISE NOTICE 'creating partition % ...', l_part_name;
   
    l_sql := format($$CREATE TABLE public."%s" PARTITION OF metrics FOR VALUES FROM ('%s') TO ('%s') PARTITION BY LIST (dbname)$$,
                    l_part_name, l_part_start, l_part_end);
    EXECUTE l_sql;
  END IF;

  l_sub_part_name := format('metrics_y%sw%s_%s', l_year, l_week, dbname);
  IF NOT EXISTS (SELECT 1
                   FROM pg_tables
                  WHERE tablename = l_sub_part_name
                    AND schemaname = 'public')
  THEN
    --RAISE NOTICE 'creating sub-partition % ...', l_sub_part_name;
    l_sql := format($$CREATE TABLE public."%s" PARTITION OF public.%s FOR VALUES IN ('%s')$$,
                    l_sub_part_name, l_part_name,  dbname);
    EXECUTE l_sql;
  END IF;

  END LOOP;

  
END;
$SQL$ LANGUAGE plpgsql;
