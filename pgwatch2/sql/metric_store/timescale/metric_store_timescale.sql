/*
  NB! Make sure you're on PG v11+ and TimescaleDB v1.7+.
  A fresh separate DB, only for pgwatch2 metrics storage purposes, is assumed.
*/
CREATE SCHEMA IF NOT EXISTS subpartitions AUTHORIZATION pgwatch2;

CREATE EXTENSION IF NOT EXISTS timescaledb;

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
create index on admin.metrics_template using gin (tag_data) where tag_data notnull;

/*
 something like below will be done by the gatherer AUTOMATICALLY via the admin.ensure_partition_timescale() function:

create table public."some_metric"
  (LIKE admin.metrics_template INCLUDING INDEXES);
COMMENT ON TABLE public."some_metric" IS 'pgwatch2-generated-metric-lvl';

ALTER TABLE some_metric SET (
  timescaledb.compress,
  timescaledb.compress_segmentby = 'dbname'
);

SELECT add_compress_chunks_policy('some_metric', INTERVAL '1 day');
-- for Timescale v2.0+:
-- PERFORM add_compression_policy('some_metric', INTERVAL '1 day');

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

insert into admin.storage_schema_type select 'timescale';
