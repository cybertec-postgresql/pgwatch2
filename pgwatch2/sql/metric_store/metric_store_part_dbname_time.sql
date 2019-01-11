/* NB! PG 11+ only, for lesser PG versions see "metric_store_simple.sql"
   This schema is recommended for 25+ monitored DBs or for short intervals /
   long retention periods i.e. gigs and gigs of data.
   Also not to create too many sub-partitions which is detrimental to query
   performance, data is split into *monthly* not weekly chunks!
*/

REVOKE ALL ON SCHEMA public FROM public;

GRANT ALL ON SCHEMA public TO pgwatch2;

CREATE EXTENSION IF NOT EXISTS btree_gin;

SET role TO pgwatch2;

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
  (LIKE public.metrics_template)
  PARTITION BY LIST (dbname);

create table public."mymetric_mydbname"
  PARTITION OF public."mymetric"
  FOR VALUES IN ('my-dbname') PARTITION BY RANGE (time);

create table public."mymetric_mydbname_y2019m01" -- month calculated dynamically of course
  PARTITION OF public."mymetric_mydbname"
  FOR VALUES FROM ('2019-01-01') TO ('2019-02-01');

*/
