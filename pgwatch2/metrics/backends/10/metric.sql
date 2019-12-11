with sa_snapshot as (
  select * from get_stat_activity()
  where pid != pg_backend_pid()
)
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  (select count(*) from sa_snapshot where backend_type = 'client backend') as total,
  (select count(*) from sa_snapshot where backend_type = 'background worker') as background_workers,
  (select count(*) from sa_snapshot where state = 'active' and backend_type = 'client backend') as active,
  (select count(*) from sa_snapshot where state = 'idle' and backend_type = 'client backend') as idle,
  (select count(*) from sa_snapshot where state = 'idle in transaction' and backend_type = 'client backend') as idleintransaction,
  (select count(*) from sa_snapshot where wait_event_type in ('LWLock', 'Lock', 'BufferPin') and backend_type = 'client backend') as waiting,
  (select extract(epoch from (now() - backend_start))::int
    from sa_snapshot where backend_type = 'client backend' order by backend_start limit 1) as longest_session_seconds,
  (select extract(epoch from (now() - xact_start))::int
    from sa_snapshot where xact_start is not null and backend_type = 'client backend' order by xact_start limit 1) as longest_tx_seconds,
  (select extract(epoch from (now() - xact_start))::int
    from get_stat_activity() where backend_type = 'autovacuum worker' order by xact_start limit 1) as longest_autovacuum_seconds,
  (select extract(epoch from max(now() - query_start))::int
    from sa_snapshot where state = 'active' and backend_type = 'client backend') as longest_query_seconds,
  (select max(age(backend_xmin))::int8 from sa_snapshot) as max_xmin_age_tx,
  (select count(*) from sa_snapshot where state = 'active' and backend_type = 'autovacuum worker') as av_workers
;
