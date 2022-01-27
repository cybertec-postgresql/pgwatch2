with sa_snapshot as (
  select * from get_stat_activity()
)
select /* pgwatch2_generated */
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  (select count(*) from sa_snapshot) as total,
  (select count(*) from pg_stat_activity where pid != pg_backend_pid()) as instance_total,
  current_setting('max_connections')::int as max_connections,
  (select count(*) from sa_snapshot where state = 'active') as active,
  (select count(*) from sa_snapshot where state = 'idle') as idle,
  (select count(*) from sa_snapshot where state = 'idle in transaction') as idleintransaction,
  (select count(*) from sa_snapshot where waiting) as waiting,
  (select ceil(extract(epoch from max(now() - query_start)))::int from sa_snapshot where waiting) as longest_waiting_seconds,
  (select round(avg(abs(extract(epoch from now() - query_start)))::numeric, 3)::float from sa_snapshot where waiting) as avg_waiting_seconds,
  (select ceil(extract(epoch from (now() - backend_start)))::int from sa_snapshot order by backend_start limit 1) as longest_session_seconds,
  (select round(avg(abs(extract(epoch from now() - backend_start)))::numeric, 3)::float from sa_snapshot) as avg_session_seconds,
  (select ceil(extract(epoch from (now() - xact_start)))::int from sa_snapshot where not query like 'autovacuum:%' and xact_start is not null order by xact_start limit 1) as longest_tx_seconds,
  (select round(avg(abs(extract(epoch from now() - xact_start)))::numeric, 3)::float from sa_snapshot where not query like 'autovacuum:%' and xact_start is not null) as avg_tx_seconds,
  (select ceil(extract(epoch from (now() - xact_start)))::int from sa_snapshot where query like 'autovacuum:%' order by xact_start limit 1) as longest_autovacuum_seconds,
  (select ceil(extract(epoch from max(now() - query_start)))::int from sa_snapshot where not query like 'autovacuum:%' and state = 'active') as longest_query_seconds,
  (select round(avg(abs(extract(epoch from now() - query_start)))::numeric, 3)::float from sa_snapshot where not query like 'autovacuum:%' and state = 'active') as avg_query_seconds,
  (select count(*) from sa_snapshot where query like 'autovacuum:%') as av_workers
;
