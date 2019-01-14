GRANT ALL ON SCHEMA public TO pgwatch2;

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
create table public.all_distinct_dbnames (
  dbname text not null primary key,
  created_on timestamptz not null default now()
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
BEGIN
  IF NOT EXISTS (SELECT 1
                   FROM pg_tables
                  WHERE tablename = metric
                    AND schemaname = 'public')
  THEN
    --RAISE NOTICE 'creating partition % ...', metric;
    EXECUTE format($$CREATE TABLE public."%s" (LIKE public.metrics_template INCLUDING INDEXES)$$, metric);
    EXECUTE format($$COMMENT ON TABLE public."%s" IS 'pgwatch2-generated-metric-lvl'$$, metric);
    RETURN true;
  END IF;
  RETURN false;
END;
$SQL$ LANGUAGE plpgsql;
GRANT EXECUTE ON FUNCTION public.ensure_dummy_metrics_table(text) TO pgwatch2;



RESET ROLE;
