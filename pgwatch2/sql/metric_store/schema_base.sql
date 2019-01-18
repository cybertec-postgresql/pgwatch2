GRANT ALL ON SCHEMA public TO pgwatch2;

DO $SQL$
BEGIN
  EXECUTE format($$ALTER ROLE pgwatch2 IN DATABASE %s SET statement_timeout TO '5min'$$, current_database());
END
$SQL$;

SET ROLE TO pgwatch2;

-- drop table if exists public.storage_schema_type;

/* although the gather has a "--pg-storage-type" param, the WebUI might not know about it in a custom setup */
create table public.storage_schema_type (
  schema_type text not null,
  initialized_on timestamptz not null default now(),
  check (schema_type in ('metric', 'metric-time', 'metric-dbname-time', 'custom'))
);

comment on table public.storage_schema_type is 'identifies storage schema for other pgwatch2 components';

create unique index max_one_row on public.storage_schema_type ((1));

/* for the Grafana drop-down. managed by the gatherer */
create table public.all_distinct_dbname_metrics (
  dbname text not null,
  metric text not null,
  created_on timestamptz not null default now(),
  primary key (dbname, metric)
);



-- DROP FUNCTION IF EXISTS public.ensure_dummy_metrics_table(text);
-- select * from public.ensure_dummy_metrics_table('wal');
CREATE OR REPLACE FUNCTION public.ensure_dummy_metrics_table(
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
BEGIN
  SELECT schema_type INTO l_schema_type FROM public.storage_schema_type;

    IF NOT EXISTS (SELECT 1
                    FROM pg_tables
                    WHERE tablename = metric
                      AND schemaname = 'public')
    THEN

      IF l_schema_type = 'metric' THEN
        EXECUTE format($$CREATE TABLE public."%s" (LIKE public.metrics_template INCLUDING INDEXES)$$, metric);
      ELSIF l_schema_type = 'metric-time' THEN
        EXECUTE format($$CREATE TABLE public."%s" (LIKE public.metrics_template INCLUDING INDEXES) PARTITION BY RANGE (time)$$, metric);
      ELSIF l_schema_type = 'metric-dbname-time' THEN
        EXECUTE format($$CREATE TABLE public."%s" (LIKE public.metrics_template INCLUDING INDEXES) PARTITION BY LIST (dbname)$$, metric);
      END IF;

      EXECUTE format($$COMMENT ON TABLE public."%s" IS 'pgwatch2-generated-metric-lvl'$$, metric);

      RETURN true;

    END IF;

  RETURN false;
END;
$SQL$ LANGUAGE plpgsql;
GRANT EXECUTE ON FUNCTION public.ensure_dummy_metrics_table(text) TO pgwatch2;



RESET ROLE;
