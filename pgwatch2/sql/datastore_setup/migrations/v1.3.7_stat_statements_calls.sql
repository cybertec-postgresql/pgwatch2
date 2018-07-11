UPDATE pgwatch2.metric
SET m_sql =
  $sql$
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  sum(calls) as calls,
  sum(total_time) as total_time
from
  public.get_stat_statements();
$sql$
WHERE
  m_name = 'stat_statements_calls'
  AND m_pg_version_from = 9.2
;
