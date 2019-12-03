/*
 "admin" schema - stores schema type, partition templates and data cleanup functions
 "public" schema - top level metric tables
 "subpartitions" schema - subpartitions of "public" schema top level metric tables (if using time / dbname-time partitioning)
*/

CREATE SCHEMA IF NOT EXISTS admin AUTHORIZATION pgwatch2;

GRANT ALL ON SCHEMA public TO pgwatch2;

DO $SQL$
BEGIN
  EXECUTE format($$ALTER ROLE pgwatch2 IN DATABASE %s SET statement_timeout TO '5min'$$, current_database());
  RAISE WARNING 'NB! Enabling asynchronous commit for pgwatch2 role - revert if possible data loss on crash is not acceptable!';
  EXECUTE format($$ALTER ROLE pgwatch2 IN DATABASE %s SET synchronous_commit TO off$$, current_database());
END
$SQL$;

SET ROLE TO pgwatch2;

-- drop table if exists public.storage_schema_type;

/* although the gather has a "--pg-storage-type" param, the WebUI might not know about it in a custom setup */
create table admin.storage_schema_type (
  schema_type text not null,
  initialized_on timestamptz not null default now(),
  check (schema_type in ('metric', 'metric-time', 'metric-dbname-time', 'custom'))
);

comment on table admin.storage_schema_type is 'identifies storage schema for other pgwatch2 components';

create unique index max_one_row on admin.storage_schema_type ((1));

/* for the Grafana drop-down. managed by the gatherer */
create table admin.all_distinct_dbname_metrics (
  dbname text not null,
  metric text not null,
  created_on timestamptz not null default now(),
  primary key (dbname, metric)
);



-- DROP FUNCTION IF EXISTS admin.ensure_dummy_metrics_table(text);
-- select * from admin.ensure_dummy_metrics_table('wal');
CREATE OR REPLACE FUNCTION admin.ensure_dummy_metrics_table(
    metric text
)
RETURNS boolean AS
/*
  creates a top level metric table if not already existing (non-existing tables show ugly warnings in Grafana).
  expects the "metrics_template" table to exist.
*/
$SQL$
DECLARE
  l_schema_type text;
  l_template_table text := 'admin.metrics_template';
  l_unlogged text := '';
BEGIN
  SELECT schema_type INTO l_schema_type FROM admin.storage_schema_type;

    IF NOT EXISTS (SELECT 1
                    FROM pg_tables
                    WHERE tablename = metric
                      AND schemaname = 'public')
    THEN
      IF metric ~ 'realtime' THEN
          l_template_table := 'admin.metrics_template_realtime';
          l_unlogged := 'UNLOGGED';
      END IF;

      IF l_schema_type = 'metric' THEN
        EXECUTE format($$CREATE %s TABLE public."%s" (LIKE %s INCLUDING INDEXES)$$, l_unlogged, metric, l_template_table);
      ELSIF l_schema_type = 'metric-time' THEN
        EXECUTE format($$CREATE %s TABLE public."%s" (LIKE %s INCLUDING INDEXES) PARTITION BY RANGE (time)$$, l_unlogged, metric, l_template_table);
      ELSIF l_schema_type = 'metric-dbname-time' THEN
        EXECUTE format($$CREATE %s TABLE public."%s" (LIKE %s INCLUDING INDEXES) PARTITION BY LIST (dbname)$$, l_unlogged, metric, l_template_table);
      END IF;

      EXECUTE format($$COMMENT ON TABLE public."%s" IS 'pgwatch2-generated-metric-lvl'$$, metric);

      RETURN true;

    END IF;

  RETURN false;
END;
$SQL$ LANGUAGE plpgsql;
GRANT EXECUTE ON FUNCTION admin.ensure_dummy_metrics_table(text) TO pgwatch2;



RESET ROLE;
