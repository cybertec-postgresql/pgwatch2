with q_sa as (
    select * from pg_stat_activity where datname = current_database() and pid <> pg_backend_pid()
)
select /* pgwatch2_generated */
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  wait_event_type as tag_wait_event_type,
  wait_event as tag_wait_event,
  count(*),
  avg(abs(1e6* extract(epoch from now() - query_start)))::int8 as avg_query_duration_us,
  max(abs(1e6* extract(epoch from now() - query_start)))::int8 as max_query_duration_us,
  (select count(*) from q_sa where state = 'active') as total_active
from
  q_sa
where
  state = 'active'
  and wait_event_type is not null
  and wait_event_type <> 'Timeout'
group by
  1, 2, 3;
