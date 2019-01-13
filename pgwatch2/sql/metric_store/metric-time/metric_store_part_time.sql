/* 
   NB! PG 11+ only (for lesser PG versions see "metric_store_simple.sql")
   This schema is recommended for <25 monitored DBs (see "metric_store_part_dbname_time.sql" for 25+).
   Use the gatherer flag "--pg-schema-type=metric-time" when using this schema.
   NB! A fresh DB, only for pgwatch2 metrics storage purposes, is assumed.
*/

CREATE SCHEMA IF NOT EXISTS subpartitions AUTHORIZATION pgwatch2;

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

create table public."mymetric"
  (LIKE public.metrics_template INCLUDING INDEXES)
  PARTITION BY RANGE (time);
COMMENT ON TABLE public."mymetric" IS 'pgwatch2-generated-metric-lvl';

create table subpartitions."mymetric_y2019w01" -- year/week calculated dynamically of course
  PARTITION OF public."mymetric"
  FOR VALUES FROM ('2019-01-01') TO ('2019-01-07');
COMMENT ON TABLE subpartitions."mymetric_y2019w01" IS 'pgwatch2-generated-metric-time-lvl';

*/

RESET ROLE;
