/* NB! PG 11+ only, for lesser PG versions see "metric_store_simple.sql"
   This schema is recommended for 25+ monitored DBs or for short intervals /
   long retention periods i.e. gigs and gigs of data.
   NB! A fresh separate DB, only for pgwatch2 metrics storage purposes, is assumed.
*/

CREATE SCHEMA IF NOT EXISTS subpartitions AUTHORIZATION pgwatch2;

CREATE EXTENSION IF NOT EXISTS btree_gin;

SET ROLE TO pgwatch2;

-- drop table if exists metrics_template;

create table admin.metrics_template (
  time timestamptz not null default now(),
  dbname text not null,
  data jsonb not null,
  tag_data jsonb,
  check (false)
);

comment on table admin.metrics_template is 'used as a template for all new metric definitions';

-- create index on admin.metrics_template using brin (dbname, time);  /* consider BRIN instead for large data amounts */
create index on admin.metrics_template (dbname, time);
create index on admin.metrics_template using gin (dbname, tag_data, time) where tag_data notnull;

/*
 something like below will be done by the gatherer AUTOMATICALLY:

create table public."mymetric"
  (LIKE admin.metrics_template)
  PARTITION BY LIST (dbname);
COMMENT ON TABLE public."mymetric" IS 'pgwatch2-generated-metric-lvl';

create table subpartitions."mymetric_mydbname"
  PARTITION OF public."mymetric"
  FOR VALUES IN ('my-dbname') PARTITION BY RANGE (time);
COMMENT ON TABLE subpartitions."mymetric_mydbname" IS 'pgwatch2-generated-metric-dbname-lvl';

create table subpartitions."mymetric_mydbname_y2019w01" -- month calculated dynamically of course
  PARTITION OF subpartitions."mymetric_mydbname"
  FOR VALUES FROM ('2019-01-01') TO ('2019-01-07');
COMMENT ON TABLE subpartitions."mymetric_mydbname_y2019w01" IS 'pgwatch2-generated-metric-dbname-time-lvl';

*/


/* "realtime" metrics are non-persistent and have 1d retention */

-- drop table if exists metrics_template_realtime;
create unlogged table admin.metrics_template_realtime (
    time timestamptz not null default now(),
    dbname text not null,
    data jsonb not null,
    tag_data jsonb,  -- no index!
    check (false)
);

comment on table admin.metrics_template_realtime is 'used as a template for all new realtime metric definitions';

-- create index on admin.metrics_template using brin (dbname, time) with (pages_per_range=32);  /* consider BRIN instead for large data amounts */
create index on admin.metrics_template_realtime (dbname, time);


RESET ROLE;

insert into admin.storage_schema_type select 'metric-dbname-time';
