with sa_snapshot as (
  select * from get_stat_activity()
)
select /* pgwatch2_generated */
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  (select count(*) from sa_snapshot where backend_type = 'client backend') as total,
  (select count(*) from pg_stat_activity where pid != pg_backend_pid()) as instance_total,
  current_setting('max_connections')::int as max_connections,
  (select count(*) from sa_snapshot where backend_type = 'background worker') as background_workers,
  (select count(*) from sa_snapshot where state = 'active' and backend_type = 'client backend') as active,
  (select count(*) from sa_snapshot where state = 'idle' and backend_type = 'client backend') as idle,
  (select count(*) from sa_snapshot where state = 'idle in transaction' and backend_type = 'client backend') as idleintransaction,
  (select count(*) from sa_snapshot where wait_event_type in ('LWLock', 'Lock', 'BufferPin') and backend_type = 'client backend') as waiting,
  (select coalesce(sum(case when coalesce(array_length(pg_blocking_pids(pid), 1), 0) >= 1 then 1 else 0 end), 0) from sa_snapshot where backend_type = 'client backend' and state = 'active') as blocked,
  (select ceil(extract(epoch from max(now() - query_start)))::int from sa_snapshot where wait_event_type in ('LWLock', 'Lock', 'BufferPin') and backend_type = 'client backend') as longest_waiting_seconds,
  (select round(avg(abs(extract(epoch from now() - query_start)))::numeric, 3)::float from sa_snapshot where wait_event_type in ('LWLock', 'Lock', 'BufferPin') and backend_type = 'client backend') as avg_waiting_seconds,
  (select ceil(extract(epoch from (now() - backend_start)))::int from sa_snapshot where backend_type = 'client backend' order by backend_start limit 1) as longest_session_seconds,
  (select round(avg(abs(extract(epoch from now() - backend_start)))::numeric, 3)::float from sa_snapshot where backend_type = 'client backend') as avg_session_seconds,
  (select ceil(extract(epoch from (now() - xact_start)))::int from sa_snapshot where xact_start is not null and backend_type = 'client backend' order by xact_start limit 1) as longest_tx_seconds,
  (select round(avg(abs(extract(epoch from now() - xact_start)))::numeric, 3)::float from sa_snapshot where xact_start is not null and backend_type = 'client backend') as avg_tx_seconds,
  (select ceil(extract(epoch from (now() - xact_start)))::int from sa_snapshot where backend_type = 'autovacuum worker' order by xact_start limit 1) as longest_autovacuum_seconds,
  (select ceil(extract(epoch from max(now() - query_start)))::int from sa_snapshot where state = 'active' and backend_type = 'client backend') as longest_query_seconds,
  (select round(avg(abs(extract(epoch from now() - query_start)))::numeric, 3)::float from sa_snapshot where state = 'active' and backend_type = 'client backend') as avg_query_seconds,
  (select max(age(backend_xmin))::int8 from sa_snapshot) as max_xmin_age_tx,
  (select count(*) from sa_snapshot where state = 'active' and backend_type = 'autovacuum worker') as av_workers
;
