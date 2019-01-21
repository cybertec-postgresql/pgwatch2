-- DROP FUNCTION IF EXISTS public.get_top_level_metric_tables();
-- select * from public.get_top_level_metric_tables();
CREATE OR REPLACE FUNCTION public.get_top_level_metric_tables(
    OUT table_name text
)
RETURNS SETOF text AS
$SQL$
  select nspname||'.'||quote_ident(c.relname) as tbl
  from pg_class c 
  join pg_namespace n on n.oid = c.relnamespace
  where relkind in ('r', 'p') and nspname = 'public'
  and exists (select 1 from pg_attribute where attrelid = c.oid and attname = 'time')
  and pg_catalog.obj_description(c.oid, 'pg_class') = 'pgwatch2-generated-metric-lvl'
  order by 1
$SQL$ LANGUAGE sql;
GRANT EXECUTE ON FUNCTION public.get_top_level_metric_tables() TO pgwatch2;


-- DROP FUNCTION IF EXISTS public.drop_all_metric_tables();
-- select * from public.drop_all_metric_tables();
CREATE OR REPLACE FUNCTION public.drop_all_metric_tables()
RETURNS int AS
$SQL$
DECLARE
  r record;
  i int := 0;
BEGIN
  FOR r IN select * from get_top_level_metric_tables()
  LOOP
    raise notice 'dropping %', r.table_name;
    EXECUTE 'DROP TABLE ' || r.table_name;
    i := i + 1;
  END LOOP;
  
  EXECUTE 'truncate public.all_distinct_dbname_metrics';
  
  RETURN i;
END;
$SQL$ LANGUAGE plpgsql;
GRANT EXECUTE ON FUNCTION public.drop_all_metric_tables() TO pgwatch2;


-- DROP FUNCTION IF EXISTS public.truncate_all_metric_tables();
-- select * from public.truncate_all_metric_tables();
CREATE OR REPLACE FUNCTION public.truncate_all_metric_tables()
RETURNS int AS
$SQL$
DECLARE
  r record;
  i int := 0;
BEGIN
  FOR r IN select * from get_top_level_metric_tables()
  LOOP
    raise notice 'dropping %', r.table_name;
    EXECUTE 'TRUNCATE TABLE ' || r.table_name;
    i := i + 1;
  END LOOP;
  
  EXECUTE 'truncate public.all_distinct_dbname_metrics';
  
  RETURN i;
END;
$SQL$ LANGUAGE plpgsql;
GRANT EXECUTE ON FUNCTION public.truncate_all_metric_tables() TO pgwatch2;


-- DROP FUNCTION IF EXISTS public.remove_single_dbname_data(text);
-- select * from public.remove_single_dbname_data('adhoc-1');
CREATE OR REPLACE FUNCTION public.remove_single_dbname_data(dbname text)
RETURNS int AS
$SQL$
DECLARE
  r record;
  i int := 0;
  j int;
  l_schema_type text;
BEGIN
  SELECT schema_type INTO l_schema_type FROM public.storage_schema_type;
  
  IF l_schema_type IN ('metric', 'metric-time') THEN
    FOR r IN select * from get_top_level_metric_tables()
    LOOP
      raise notice 'deleting data for %', r.table_name;
      EXECUTE format('DELETE FROM %s WHERE dbname = $1', r.table_name) USING dbname;
      GET DIAGNOSTICS j = ROW_COUNT;
      i := i + j;
    END LOOP;
  ELSIF l_schema_type = 'metric-dbname-time' THEN
    FOR r IN (
        select 'subpartitions.'|| quote_ident(c.relname) as table_name
                from pg_class c
                join pg_namespace n on n.oid = c.relnamespace
                where relkind in ('r', 'p') and nspname = 'subpartitions'
                and exists (select 1 from pg_attribute where attrelid = c.oid and attname = 'time')
                and pg_catalog.obj_description(c.oid, 'pg_class') = 'pgwatch2-generated-metric-dbname-lvl'
                and relname like '%_' || dbname
                order by 1
    )
    LOOP
        raise notice 'dropping sub-partition % ...', r.table_name;
        EXECUTE 'drop table ' || r.table_name;
        GET DIAGNOSTICS j = ROW_COUNT;
        i := i + j;
    END LOOP;
  ELSE
    raise exception 'unsupported schema type: %', l_schema_type;
  END IF;
  
  EXECUTE 'delete from public.all_distinct_dbname_metrics where dbname = $1' USING dbname;
  
  RETURN i;
END;
$SQL$ LANGUAGE plpgsql;
GRANT EXECUTE ON FUNCTION public.remove_single_dbname_data(text) TO pgwatch2;
