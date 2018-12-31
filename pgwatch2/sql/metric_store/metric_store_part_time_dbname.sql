/* NB! PG 11+ only.
   For lesser PG versions see "metric_store_simple.sql"
*/

REVOKE ALL ON SCHEMA public FROM public;

GRANT ALL ON SCHEMA public TO pgwatch2;

CREATE EXTENSION IF NOT EXISTS btree_gin;

SET role TO pgwatch2;

create table metrics (
  time timestamptz not null default now(),
  dbname text not null,
  metric text not null,
  data jsonb not null,
  tag_data jsonb
) PARTITION BY RANGE (time);


create index on metrics (metric, time);
create index on metrics using gin (tag_data, time);
