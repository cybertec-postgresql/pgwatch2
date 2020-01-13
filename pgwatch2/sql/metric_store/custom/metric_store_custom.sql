/*
  NB! Custom schema is for those cases where the available presets are not satisfactory / applicable.
  Then the metrics gathering daemon will try to insert all metrics into the "metrics" table and the user
  can freely re-route the data however he likes with an according trigger. In that case also data
  all table creation and data cleanup must be performed by the user. Can be used also when only having
  a couple of DB-s and performance / minimal storage is no issue.
*/

SET ROLE TO pgwatch2;

-- drop table if exists metrics;

create table public.metrics (
  time timestamptz not null default now(),
  dbname text not null,
  metric text not null,
  data jsonb not null,
  tag_data jsonb
);

comment on table public.metrics is 'a master table for "custom" mode';

/* suggested indexes */
create index on public.metrics (dbname, metric, time);
create index on public.metrics using gin (metric, tag_data, time) where tag_data notnull;

RESET ROLE;
