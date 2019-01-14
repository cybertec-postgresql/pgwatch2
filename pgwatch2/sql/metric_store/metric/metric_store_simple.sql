/*
  NB! When possible the partitioned versions ("metric_store_part_time.sql"
  or "metric_store_part_dbname_time.sql") (assuming PG10+) should be used
  as much less IO would be then performed when removing old data.
  Use the gatherer flag "--pg-schema-type=metric" when using this schema.
  NB! A fresh DB, only for pgwatch2 metrics storage purposes, is assumed.
*/

CREATE EXTENSION IF NOT EXISTS btree_gin;

SET ROLE TO pgwatch2;

-- drop table if exists metrics_template;

create table public.metrics_template (
  time timestamptz not null default now(),
  dbname text not null,
  data jsonb not null,
  tag_data jsonb,
  check (false)
);

comment on table public.metrics_template is 'used as a template for all new metric definitions';

create index on public.metrics_template (dbname, time);
create index on public.metrics_template using gin (dbname, tag_data, time);

/*
 something like below will be done by the gatherer AUTOMATICALLY:

create table public."some-metric"
  (LIKE public.metrics_template INCLUDING INDEXES);
COMMENT ON TABLE public."some-metric" IS 'pgwatch2-generated-metric-lvl';

*/

RESET ROLE;

insert into public.storage_schema_type select 'metric';
