-- DROP FUNCTION IF EXISTS admin.get_top_level_metric_tables();
-- select * from admin.get_top_level_metric_tables();
CREATE OR REPLACE FUNCTION admin.get_top_level_metric_tables(
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
GRANT EXECUTE ON FUNCTION admin.get_top_level_metric_tables() TO pgwatch2;


-- DROP FUNCTION IF EXISTS admin.drop_all_metric_tables();
-- select * from admin.drop_all_metric_tables();
CREATE OR REPLACE FUNCTION admin.drop_all_metric_tables()
RETURNS int AS
$SQL$
DECLARE
  r record;
  i int := 0;
BEGIN
  FOR r IN select * from admin.get_top_level_metric_tables()
  LOOP
    raise notice 'dropping %', r.table_name;
    EXECUTE 'DROP TABLE ' || r.table_name;
    i := i + 1;
  END LOOP;
  
  EXECUTE 'truncate admin.all_distinct_dbname_metrics';
  
  RETURN i;
END;
$SQL$ LANGUAGE plpgsql;
GRANT EXECUTE ON FUNCTION admin.drop_all_metric_tables() TO pgwatch2;


-- DROP FUNCTION IF EXISTS admin.truncate_all_metric_tables();
-- select * from admin.truncate_all_metric_tables();
CREATE OR REPLACE FUNCTION admin.truncate_all_metric_tables()
RETURNS int AS
$SQL$
DECLARE
  r record;
  i int := 0;
BEGIN
  FOR r IN select * from admin.get_top_level_metric_tables()
  LOOP
    raise notice 'dropping %', r.table_name;
    EXECUTE 'TRUNCATE TABLE ' || r.table_name;
    i := i + 1;
  END LOOP;
  
  EXECUTE 'truncate admin.all_distinct_dbname_metrics';
  
  RETURN i;
END;
$SQL$ LANGUAGE plpgsql;
GRANT EXECUTE ON FUNCTION admin.truncate_all_metric_tables() TO pgwatch2;


-- DROP FUNCTION IF EXISTS admin.remove_single_dbname_data(text);
-- select * from admin.remove_single_dbname_data('adhoc-1');
CREATE OR REPLACE FUNCTION admin.remove_single_dbname_data(dbname text)
RETURNS int AS
$SQL$
DECLARE
  r record;
  i int := 0;
  j int;
  l_schema_type text;
BEGIN
  SELECT schema_type INTO l_schema_type FROM admin.storage_schema_type;
  
  IF l_schema_type IN ('metric', 'metric-time') THEN
    FOR r IN select * from admin.get_top_level_metric_tables()
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
                join pg_inherits i ON c.oid=i.inhrelid                
                join pg_class c2 on i.inhparent = c2.oid
                where c.relkind in ('r', 'p') and nspname = 'subpartitions'
                and exists (select 1 from pg_attribute where attrelid = c.oid and attname = 'time')
                and pg_catalog.obj_description(c.oid, 'pg_class') = 'pgwatch2-generated-metric-dbname-lvl'
                and (regexp_match(pg_catalog.pg_get_expr(c.relpartbound, c.oid), E'FOR VALUES IN \\(''(.*)''\\)'))[1] = dbname
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
  
  EXECUTE 'delete from admin.all_distinct_dbname_metrics where dbname = $1' USING dbname;
  
  RETURN i;
END;
$SQL$ LANGUAGE plpgsql;
GRANT EXECUTE ON FUNCTION admin.remove_single_dbname_data(text) TO pgwatch2;


-- drop function if exists admin.drop_old_time_partitions(int,bool)
-- select * from admin.drop_old_time_partitions(1, true);
CREATE OR REPLACE FUNCTION admin.drop_old_time_partitions(older_than_days int, dry_run boolean default true)
RETURNS int AS
$SQL$
DECLARE
  r record;
  i int := 0;
  l_schema_type text;
BEGIN

  SELECT schema_type INTO l_schema_type FROM admin.storage_schema_type;

  IF l_schema_type IN ('metric-time', 'metric-dbname-time') THEN

    FOR r IN (
      SELECT time_partition_name FROM (
        SELECT
            'subpartitions.' || quote_ident(c.relname) as time_partition_name,
            pg_catalog.pg_get_expr(c.relpartbound, c.oid) as limits,
            (regexp_match(pg_catalog.pg_get_expr(c.relpartbound, c.oid),
                E'TO \\((''.*?'')'))[1]::timestamp < (current_date  - '1day'::interval * (case when c.relname::text ~ 'realtime' then 0 else older_than_days end)) is_old
        FROM
            pg_class c
          JOIN
            pg_inherits i ON c.oid=i.inhrelid
            JOIN
            pg_namespace n ON n.oid = relnamespace
        WHERE
          c.relkind IN ('r', 'p')
            AND nspname = 'subpartitions'
            AND pg_catalog.obj_description(c.oid, 'pg_class') IN (
              'pgwatch2-generated-metric-time-lvl',
              'pgwatch2-generated-metric-dbname-time-lvl'
            )
        ) x
        WHERE is_old
        ORDER BY 1
    )
    LOOP
      if dry_run then
        raise notice 'would drop old time sub-partition: %', r.time_partition_name;
      else
        raise notice 'dropping old time sub-partition: %', r.time_partition_name;
        EXECUTE 'drop table ' || r.time_partition_name;
        i := i + 1;
      end if;
    END LOOP;

  ELSE
    raise warning 'unsupported schema type: %', l_schema_type;
  END IF;

  RETURN i;
END;
$SQL$ LANGUAGE plpgsql;
GRANT EXECUTE ON FUNCTION admin.drop_old_time_partitions(int,bool) TO pgwatch2;
