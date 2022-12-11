select /* pgwatch2_generated */
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  s.query as query,
  count(*) as count
from pg_stat_activity s
where s.datname = current_database()
  and s.state = 'active'
  and s.backend_type = 'client backend'
  and s.pid != pg_backend_pid()
  and now() - s.query_start > '100ms'::interval
group by s.query;
