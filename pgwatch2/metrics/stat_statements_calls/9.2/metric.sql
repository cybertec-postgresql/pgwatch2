select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  sum(calls) as calls,
  sum(total_time) as total_time
from
  public.get_stat_statements();
