select /* pgwatch2_generated */
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  coalesce(sum(calls), 0)::int8 as calls,
  coalesce(round(sum(total_exec_time)::numeric, 3), 0)::float8 as total_time,
  round(sum(total_plan_time)::numeric, 3)::double precision as total_plan_time
from
  pg_stat_statements
where
  dbid = (select oid from pg_database where datname = current_database())
;
