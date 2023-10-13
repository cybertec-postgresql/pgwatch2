/* METRIC DEFINITIONS + METRIC ATTRIBUTES below */

-- truncate pgwatch2.metric;

/* backends */

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs, m_sql_su)
values (
'backends',
9.0,
$sql$
with sa_snapshot as (
  select * from get_stat_activity()
)
select
    (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
    (select count(*) from sa_snapshot) as total,
    (select count(*) from pg_stat_activity where procpid != pg_backend_pid()) as instance_total,
    current_setting('max_connections')::int as max_connections,
    (select count(*) from sa_snapshot where current_query != '<IDLE>') as active,
    (select count(*) from sa_snapshot where current_query = '<IDLE>') as idle,
    (select count(*) from sa_snapshot where current_query = '<IDLE> in transaction') as idleintransaction,
    (select count(*) from sa_snapshot where waiting) as waiting,
    (select ceil(extract(epoch from max(now() - query_start)))::int from sa_snapshot where waiting) as longest_waiting_seconds,
    (select round(avg(abs(extract(epoch from now() - query_start)))::numeric, 3)::float from sa_snapshot where waiting) as avg_waiting_seconds,
    (select ceil(extract(epoch from (now() - backend_start)))::int from sa_snapshot order by backend_start limit 1) as longest_session_seconds,
    (select round(avg(abs(extract(epoch from now() - backend_start)))::numeric, 3)::float from sa_snapshot) as avg_session_seconds,
    (select ceil(extract(epoch from (now() - xact_start)))::int from sa_snapshot where not current_query like 'autovacuum:%' and xact_start is not null order by xact_start limit 1) as longest_tx_seconds,
    (select round(avg(abs(extract(epoch from now() - xact_start)))::numeric, 3)::float from sa_snapshot where not current_query like 'autovacuum:%' and xact_start is not null) as avg_tx_seconds,
    (select ceil(extract(epoch from (now() - xact_start)))::int from sa_snapshot where current_query like 'autovacuum:%' order by xact_start limit 1) as longest_autovacuum_seconds,
    (select ceil(extract(epoch from max(now() - query_start)))::int from sa_snapshot where not current_query like 'autovacuum:%' and current_query != '<IDLE>') as longest_query_seconds,
    (select round(avg(abs(extract(epoch from now() - query_start)))::numeric, 3)::float from sa_snapshot where not current_query like 'autovacuum:%' and current_query != '<IDLE>') as avg_query_seconds,
    (select count(*) from sa_snapshot where current_query like 'autovacuum:%') as av_workers
;
$sql$,
'{"prometheus_all_gauge_columns": true}',
$sql$
with sa_snapshot as (
  select * from pg_stat_activity
  where datname = current_database()
  and procpid != pg_backend_pid()
)
select
    (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
    (select count(*) from sa_snapshot) as total,
    (select count(*) from pg_stat_activity where procpid != pg_backend_pid()) as instance_total,
    current_setting('max_connections')::int as max_connections,
    (select count(*) from sa_snapshot where current_query != '<IDLE>') as active,
    (select count(*) from sa_snapshot where current_query = '<IDLE>') as idle,
    (select count(*) from sa_snapshot where current_query = '<IDLE> in transaction') as idleintransaction,
    (select count(*) from sa_snapshot where waiting) as waiting,
    (select ceil(extract(epoch from max(now() - query_start)))::int from sa_snapshot where waiting) as longest_waiting_seconds,
    (select round(avg(abs(extract(epoch from now() - query_start)))::numeric, 3)::float from sa_snapshot where waiting) as avg_waiting_seconds,
    (select ceil(extract(epoch from (now() - backend_start)))::int from sa_snapshot order by backend_start limit 1) as longest_session_seconds,
    (select round(avg(abs(extract(epoch from now() - backend_start)))::numeric, 3)::float from sa_snapshot) as avg_session_seconds,
    (select ceil(extract(epoch from (now() - xact_start)))::int from sa_snapshot where not current_query like 'autovacuum:%' and xact_start is not null order by xact_start limit 1) as longest_tx_seconds,
    (select round(avg(abs(extract(epoch from now() - xact_start)))::numeric, 3)::float from sa_snapshot where not current_query like 'autovacuum:%' and xact_start is not null) as avg_tx_seconds,
    (select ceil(extract(epoch from (now() - xact_start)))::int from sa_snapshot where current_query like 'autovacuum:%' order by xact_start limit 1) as longest_autovacuum_seconds,
    (select ceil(extract(epoch from max(now() - query_start)))::int from sa_snapshot where not current_query like 'autovacuum:%' and current_query != '<IDLE>') as longest_query_seconds,
    (select round(avg(abs(extract(epoch from now() - query_start)))::numeric, 3)::float from sa_snapshot where not current_query like 'autovacuum:%' and current_query != '<IDLE>') as avg_query_seconds,
    (select count(*) from sa_snapshot where current_query like 'autovacuum:%') as av_workers
;
$sql$
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs, m_sql_su)
values (
'backends',
9.2,
$sql$
with sa_snapshot as (
  select * from get_stat_activity()
)
select
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
$sql$,
'{"prometheus_all_gauge_columns": true}',
$sql$
with sa_snapshot as (
  select * from pg_stat_activity
  where datname = current_database()
  and pid != pg_backend_pid()
)
select
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
$sql$
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs, m_sql_su)
values (
'backends',
9.4,
$sql$
with sa_snapshot as (
  select * from get_stat_activity()
)
select
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
    (select max(age(backend_xmin))::int8 from sa_snapshot) as max_xmin_age_tx,
    (select count(*) from sa_snapshot where query like 'autovacuum:%') as av_workers
;
$sql$,
'{"prometheus_all_gauge_columns": true}',
$sql$
with sa_snapshot as (
  select * from pg_stat_activity
  where datname = current_database()
  and pid != pg_backend_pid()
)
select
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
    (select max(age(backend_xmin))::int8 from sa_snapshot) as max_xmin_age_tx,
    (select count(*) from sa_snapshot where query like 'autovacuum:%') as av_workers
;
$sql$
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs, m_sql_su)
values (
'backends',
9.6,
$sql$
with sa_snapshot as (
  select * from get_stat_activity()
)
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  (select count(*) from sa_snapshot) as total,
  (select count(*) from pg_stat_activity where pid != pg_backend_pid()) as instance_total,
  current_setting('max_connections')::int as max_connections,
  (select count(*) from sa_snapshot where state = 'active') as active,
  (select count(*) from sa_snapshot where state = 'idle') as idle,
  (select count(*) from sa_snapshot where state = 'idle in transaction') as idleintransaction,
  (select count(*) from sa_snapshot where wait_event_type in ('LWLockNamed', 'Lock', 'BufferPin')) as waiting,
  (select coalesce(sum(case when coalesce(array_length(pg_blocking_pids(pid), 1), 0) >= 1 then 1 else 0 end), 0) from sa_snapshot where state = 'active') as blocked,
  (select ceil(extract(epoch from max(now() - query_start)))::int from sa_snapshot where wait_event_type in ('LWLockNamed', 'Lock', 'BufferPin')) as longest_waiting_seconds,
  (select round(avg(abs(extract(epoch from now() - query_start)))::numeric, 3)::float from sa_snapshot where wait_event_type in ('LWLockNamed', 'Lock', 'BufferPin')) as avg_waiting_seconds,
  (select ceil(extract(epoch from (now() - backend_start)))::int from sa_snapshot order by backend_start limit 1) as longest_session_seconds,
  (select round(avg(abs(extract(epoch from now() - backend_start)))::numeric, 3)::float from sa_snapshot) as avg_session_seconds,
  (select ceil(extract(epoch from (now() - xact_start)))::int from sa_snapshot where not query like 'autovacuum:%' and xact_start is not null order by xact_start limit 1) as longest_tx_seconds,
  (select round(avg(abs(extract(epoch from now() - xact_start)))::numeric, 3)::float from sa_snapshot where not query like 'autovacuum:%' and xact_start is not null) as avg_tx_seconds,
  (select ceil(extract(epoch from (now() - xact_start)))::int from sa_snapshot where query like 'autovacuum:%' order by xact_start limit 1) as longest_autovacuum_seconds,
  (select ceil(extract(epoch from max(now() - query_start)))::int from sa_snapshot where not query like 'autovacuum:%' and state = 'active') as longest_query_seconds,
  (select round(avg(abs(extract(epoch from now() - query_start)))::numeric, 3)::float from sa_snapshot where not query like 'autovacuum:%' and state = 'active') as avg_query_seconds,
  (select max(age(backend_xmin))::int8 from sa_snapshot) as max_xmin_age_tx,
  (select count(*) from sa_snapshot where query like 'autovacuum:%') as av_workers
;
$sql$,
'{"prometheus_all_gauge_columns": true}',
$sql$
with sa_snapshot as (
  select * from pg_stat_activity
  where datname = current_database()
  and pid != pg_backend_pid()
)
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  (select count(*) from sa_snapshot) as total,
  (select count(*) from pg_stat_activity where pid != pg_backend_pid()) as instance_total,
  current_setting('max_connections')::int as max_connections,
  (select count(*) from sa_snapshot where state = 'active') as active,
  (select count(*) from sa_snapshot where state = 'idle') as idle,
  (select count(*) from sa_snapshot where state = 'idle in transaction') as idleintransaction,
  (select count(*) from sa_snapshot where wait_event_type in ('LWLockNamed', 'Lock', 'BufferPin')) as waiting,
  (select coalesce(sum(case when coalesce(array_length(pg_blocking_pids(pid), 1), 0) >= 1 then 1 else 0 end), 0) from sa_snapshot where state = 'active') as blocked,
  (select ceil(extract(epoch from max(now() - query_start)))::int from sa_snapshot where wait_event_type in ('LWLockNamed', 'Lock', 'BufferPin')) as longest_waiting_seconds,
  (select round(avg(abs(extract(epoch from now() - query_start)))::numeric, 3)::float from sa_snapshot where wait_event_type in ('LWLockNamed', 'Lock', 'BufferPin')) as avg_waiting_seconds,
  (select ceil(extract(epoch from (now() - backend_start)))::int from sa_snapshot order by backend_start limit 1) as longest_session_seconds,
  (select round(avg(abs(extract(epoch from now() - backend_start)))::numeric, 3)::float from sa_snapshot) as avg_session_seconds,
  (select ceil(extract(epoch from (now() - xact_start)))::int from sa_snapshot where not query like 'autovacuum:%' and xact_start is not null order by xact_start limit 1) as longest_tx_seconds,
  (select round(avg(abs(extract(epoch from now() - xact_start)))::numeric, 3)::float from sa_snapshot where not query like 'autovacuum:%' and xact_start is not null) as avg_tx_seconds,
  (select ceil(extract(epoch from (now() - xact_start)))::int from sa_snapshot where query like 'autovacuum:%' order by xact_start limit 1) as longest_autovacuum_seconds,
  (select ceil(extract(epoch from max(now() - query_start)))::int from sa_snapshot where not query like 'autovacuum:%' and state = 'active') as longest_query_seconds,
  (select round(avg(abs(extract(epoch from now() - query_start)))::numeric, 3)::float from sa_snapshot where not query like 'autovacuum:%' and state = 'active') as avg_query_seconds,
  (select max(age(backend_xmin))::int8 from sa_snapshot) as max_xmin_age_tx,
  (select count(*) from sa_snapshot where query like 'autovacuum:%') as av_workers
;
$sql$
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs, m_sql_su)
values (
'backends',
10,
$sql$
with sa_snapshot as (
  select * from get_stat_activity()
)
select
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
$sql$,
'{"prometheus_all_gauge_columns": true}',
$sql$
with sa_snapshot as (
  select * from pg_stat_activity
  where pid != pg_backend_pid()
  and datname = current_database()
)
select
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
$sql$
);

/* bgwriter */


insert into pgwatch2.metric(m_name, m_pg_version_from, m_master_only, m_sql)
values (
'bgwriter',
9.0,
true,
$sql$
select
   (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
   checkpoints_timed,
   checkpoints_req,
   buffers_checkpoint,
   buffers_clean,
   maxwritten_clean,
   buffers_backend,
   buffers_alloc
 from
   pg_stat_bgwriter;
$sql$
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_master_only, m_sql)
values (
'bgwriter',
9.2,
true,
$sql$
select
   (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
   checkpoints_timed,
   checkpoints_req,
   checkpoint_write_time,
   checkpoint_sync_time,
   buffers_checkpoint,
   buffers_clean,
   maxwritten_clean,
   buffers_backend,
   buffers_backend_fsync,
   buffers_alloc
 from
   pg_stat_bgwriter;
$sql$
);

/* cpu_load */

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs)
values (
'cpu_load',
9.0,
$sql$
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  round(load_1min::numeric, 2)::float as load_1min,
  round(load_5min::numeric, 2)::float as load_5min,
  round(load_15min::numeric, 2)::float as load_15min
from
  get_load_average();   -- needs the plpythonu proc from "metric_fetching_helpers" folder
$sql$,
'{"prometheus_all_gauge_columns": true}'
);


/* db_stats */

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs)
values (
'db_stats',
9.0,
$sql$
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  numbackends,
  xact_commit,
  xact_rollback,
  blks_read,
  blks_hit,
  tup_returned,
  tup_fetched,
  tup_inserted,
  tup_updated,
  tup_deleted,
  extract(epoch from (now() - pg_postmaster_start_time()))::int8 as postmaster_uptime_s,
  case when pg_is_in_recovery() then 1 else 0 end as in_recovery_int
from
  pg_stat_database
where
  datname = current_database();
$sql$,
'{"prometheus_gauge_columns": ["numbackends", "postmaster_uptime_s"]}'
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs)
values (
'db_stats',
9.1,
$sql$
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  numbackends,
  xact_commit,
  xact_rollback,
  blks_read,
  blks_hit,
  tup_returned,
  tup_fetched,
  tup_inserted,
  tup_updated,
  tup_deleted,
  conflicts,
  extract(epoch from (now() - pg_postmaster_start_time()))::int8 as postmaster_uptime_s,
  case when pg_is_in_recovery() then 1 else 0 end as in_recovery_int
from
  pg_stat_database
where
  datname = current_database();
$sql$,
'{"prometheus_gauge_columns": ["numbackends", "postmaster_uptime_s"]}'
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs)
values (
'db_stats',
9.2,
$sql$
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  numbackends,
  xact_commit,
  xact_rollback,
  blks_read,
  blks_hit,
  tup_returned,
  tup_fetched,
  tup_inserted,
  tup_updated,
  tup_deleted,
  conflicts,
  temp_files,
  temp_bytes,
  deadlocks,
  blk_read_time,
  blk_write_time,
  extract(epoch from (now() - pg_postmaster_start_time()))::int8 as postmaster_uptime_s,
  case when pg_is_in_recovery() then 1 else 0 end as in_recovery_int
from
  pg_stat_database
where
  datname = current_database();
$sql$,
'{"prometheus_gauge_columns": ["numbackends", "postmaster_uptime_s"]}'
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs)
values (
'db_stats',
9.3,
$sql$
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  numbackends,
  xact_commit,
  xact_rollback,
  blks_read,
  blks_hit,
  tup_returned,
  tup_fetched,
  tup_inserted,
  tup_updated,
  tup_deleted,
  conflicts,
  temp_files,
  temp_bytes,
  deadlocks,
  blk_read_time,
  blk_write_time,
  extract(epoch from (now() - pg_postmaster_start_time()))::int8 as postmaster_uptime_s,
  extract(epoch from (now() - pg_backup_start_time()))::int8 as backup_duration_s,
  case when pg_is_in_recovery() then 1 else 0 end as in_recovery_int
from
  pg_stat_database
where
  datname = current_database();
$sql$,
'{"prometheus_gauge_columns": ["numbackends", "postmaster_uptime_s", "backup_duration_s"]}'
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_sql_su, m_column_attrs)
values (
'db_stats',
10,
$sql$
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  numbackends,
  xact_commit,
  xact_rollback,
  blks_read,
  blks_hit,
  tup_returned,
  tup_fetched,
  tup_inserted,
  tup_updated,
  tup_deleted,
  conflicts,
  temp_files,
  temp_bytes,
  deadlocks,
  blk_read_time,
  blk_write_time,
  extract(epoch from (now() - pg_postmaster_start_time()))::int8 as postmaster_uptime_s,
  extract(epoch from (now() - pg_backup_start_time()))::int8 as backup_duration_s,
  case when pg_is_in_recovery() then 1 else 0 end as in_recovery_int,
  system_identifier::text as tag_sys_id,
  (select count(*) from pg_index i
    where not indisvalid
    and not exists ( /* leave out ones that are being actively rebuilt */
      select * from pg_locks l
      join pg_stat_activity a using (pid)
      where l.relation = i.indexrelid
      and a.state = 'active'
      and a.query ~* 'concurrently'
  )) as invalid_indexes  
from
  pg_stat_database, pg_control_system()
where
  datname = current_database();
$sql$,
$sql$
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  numbackends,
  xact_commit,
  xact_rollback,
  blks_read,
  blks_hit,
  tup_returned,
  tup_fetched,
  tup_inserted,
  tup_updated,
  tup_deleted,
  conflicts,
  temp_files,
  temp_bytes,
  deadlocks,
  blk_read_time,
  blk_write_time,
  extract(epoch from (now() - coalesce((pg_stat_file('postmaster.pid', true)).modification, pg_postmaster_start_time())))::int8 as postmaster_uptime_s,
  extract(epoch from (now() - pg_backup_start_time()))::int8 as backup_duration_s,
  case when pg_is_in_recovery() then 1 else 0 end as in_recovery_int,
  system_identifier::text as tag_sys_id,
  (select count(*) from pg_index i
    where not indisvalid
    and not exists ( /* leave out ones that are being actively rebuilt */
      select * from pg_locks l
      join pg_stat_activity a using (pid)
      where l.relation = i.indexrelid
      and a.state = 'active'
      and a.query ~* 'concurrently'
  )) as invalid_indexes  
from
  pg_stat_database, pg_control_system()
where
  datname = current_database();
$sql$,
'{"prometheus_gauge_columns": ["numbackends", "postmaster_uptime_s", "backup_duration_s"]}'
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_sql_su, m_column_attrs)
values (
'db_stats',
12,
$sql$
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  numbackends,
  xact_commit,
  xact_rollback,
  blks_read,
  blks_hit,
  tup_returned,
  tup_fetched,
  tup_inserted,
  tup_updated,
  tup_deleted,
  conflicts,
  temp_files,
  temp_bytes,
  deadlocks,
  blk_read_time,
  blk_write_time,
  extract(epoch from (now() - pg_postmaster_start_time()))::int8 as postmaster_uptime_s,
  extract(epoch from (now() - pg_backup_start_time()))::int8 as backup_duration_s,
  checksum_failures,
  extract(epoch from (now() - checksum_last_failure))::int8 as checksum_last_failure_s,
  case when pg_is_in_recovery() then 1 else 0 end as in_recovery_int,
  system_identifier::text as tag_sys_id,
  (select count(*) from pg_index i
    where not indisvalid
    and not exists ( /* leave out ones that are being actively rebuilt */
      select * from pg_locks l
      join pg_stat_activity a using (pid)
      where l.relation = i.indexrelid
      and a.state = 'active'
      and a.query ~* 'concurrently'
  )) as invalid_indexes  
from
  pg_stat_database, pg_control_system()
where
  datname = current_database();
$sql$,
$sql$
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  numbackends,
  xact_commit,
  xact_rollback,
  blks_read,
  blks_hit,
  tup_returned,
  tup_fetched,
  tup_inserted,
  tup_updated,
  tup_deleted,
  conflicts,
  temp_files,
  temp_bytes,
  deadlocks,
  blk_read_time,
  blk_write_time,
  extract(epoch from (now() - coalesce((pg_stat_file('postmaster.pid', true)).modification, pg_postmaster_start_time())))::int8 as postmaster_uptime_s,
  extract(epoch from (now() - pg_backup_start_time()))::int8 as backup_duration_s,
  checksum_failures,
  extract(epoch from (now() - checksum_last_failure))::int8 as checksum_last_failure_s,
  case when pg_is_in_recovery() then 1 else 0 end as in_recovery_int,
  system_identifier::text as tag_sys_id,
  (select count(*) from pg_index i
    where not indisvalid
    and not exists ( /* leave out ones that are being actively rebuilt */
      select * from pg_locks l
      join pg_stat_activity a using (pid)
      where l.relation = i.indexrelid
      and a.state = 'active'
      and a.query ~* 'concurrently'
  )) as invalid_indexes  
from
  pg_stat_database, pg_control_system()
where
  datname = current_database();
$sql$,
'{"prometheus_gauge_columns": ["numbackends", "postmaster_uptime_s", "backup_duration_s", "checksum_last_failure_s"]}'
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_sql_su, m_column_attrs)
values (
'db_stats',
14,
$sql$
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  numbackends,
  xact_commit,
  xact_rollback,
  blks_read,
  blks_hit,
  tup_returned,
  tup_fetched,
  tup_inserted,
  tup_updated,
  tup_deleted,
  conflicts,
  temp_files,
  temp_bytes,
  deadlocks,
  blk_read_time,
  blk_write_time,
  extract(epoch from (now() - pg_postmaster_start_time()))::int8 as postmaster_uptime_s,
  extract(epoch from (now() - pg_backup_start_time()))::int8 as backup_duration_s,
  checksum_failures,
  extract(epoch from (now() - checksum_last_failure))::int8 as checksum_last_failure_s,
  case when pg_is_in_recovery() then 1 else 0 end as in_recovery_int,
  system_identifier::text as tag_sys_id,
  session_time::int8,
  active_time::int8,
  idle_in_transaction_time::int8,
  sessions,
  sessions_abandoned,
  sessions_fatal,
  sessions_killed,
  (select count(*) from pg_index i
    where not indisvalid
    and not exists ( /* leave out ones that are being actively rebuilt */
      select * from pg_locks l
      join pg_stat_activity a using (pid)
      where l.relation = i.indexrelid
      and a.state = 'active'
      and a.query ~* 'concurrently'
  )) as invalid_indexes
from
  pg_stat_database, pg_control_system()
where
  datname = current_database();
$sql$,
$sql$
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  numbackends,
  xact_commit,
  xact_rollback,
  blks_read,
  blks_hit,
  tup_returned,
  tup_fetched,
  tup_inserted,
  tup_updated,
  tup_deleted,
  conflicts,
  temp_files,
  temp_bytes,
  deadlocks,
  blk_read_time,
  blk_write_time,
  extract(epoch from (now() - coalesce((pg_stat_file('postmaster.pid', true)).modification, pg_postmaster_start_time())))::int8 as postmaster_uptime_s,
  extract(epoch from (now() - pg_backup_start_time()))::int8 as backup_duration_s,
  checksum_failures,
  extract(epoch from (now() - checksum_last_failure))::int8 as checksum_last_failure_s,
  case when pg_is_in_recovery() then 1 else 0 end as in_recovery_int,
  system_identifier::text as tag_sys_id,
  session_time::int8,
  active_time::int8,
  idle_in_transaction_time::int8,
  sessions,
  sessions_abandoned,
  sessions_fatal,
  sessions_killed,
  (select count(*) from pg_index i
    where not indisvalid
    and not exists ( /* leave out ones that are being actively rebuilt */
      select * from pg_locks l
      join pg_stat_activity a using (pid)
      where l.relation = i.indexrelid
      and a.state = 'active'
      and a.query ~* 'concurrently'
  )) as invalid_indexes  
from
  pg_stat_database, pg_control_system()
where
  datname = current_database();
$sql$,
'{"prometheus_gauge_columns": ["numbackends", "postmaster_uptime_s", "backup_duration_s", "checksum_last_failure_s"]}'
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_sql_su, m_column_attrs)
values (
'db_stats',
15,
$sql$
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  numbackends,
  xact_commit,
  xact_rollback,
  blks_read,
  blks_hit,
  tup_returned,
  tup_fetched,
  tup_inserted,
  tup_updated,
  tup_deleted,
  conflicts,
  temp_files,
  temp_bytes,
  deadlocks,
  blk_read_time,
  blk_write_time,
  extract(epoch from (now() - pg_postmaster_start_time()))::int8 as postmaster_uptime_s,
  checksum_failures,
  extract(epoch from (now() - checksum_last_failure))::int8 as checksum_last_failure_s,
  case when pg_is_in_recovery() then 1 else 0 end as in_recovery_int,
  system_identifier::text as tag_sys_id,
  session_time::int8,
  active_time::int8,
  idle_in_transaction_time::int8,
  sessions,
  sessions_abandoned,
  sessions_fatal,
  sessions_killed,
  (select count(*) from pg_index i
    where not indisvalid
    and not exists ( /* leave out ones that are being actively rebuilt */
      select * from pg_locks l
      join pg_stat_activity a using (pid)
      where l.relation = i.indexrelid
      and a.state = 'active'
      and a.query ~* 'concurrently'
  )) as invalid_indexes  
from
  pg_stat_database, pg_control_system()
where
  datname = current_database();
$sql$,
$sql$
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  numbackends,
  xact_commit,
  xact_rollback,
  blks_read,
  blks_hit,
  tup_returned,
  tup_fetched,
  tup_inserted,
  tup_updated,
  tup_deleted,
  conflicts,
  temp_files,
  temp_bytes,
  deadlocks,
  blk_read_time,
  blk_write_time,
  extract(epoch from (now() - coalesce((pg_stat_file('postmaster.pid', true)).modification, pg_postmaster_start_time())))::int8 as postmaster_uptime_s,
  checksum_failures,
  extract(epoch from (now() - checksum_last_failure))::int8 as checksum_last_failure_s,
  case when pg_is_in_recovery() then 1 else 0 end as in_recovery_int,
  system_identifier::text as tag_sys_id,
  session_time::int8,
  active_time::int8,
  idle_in_transaction_time::int8,
  sessions,
  sessions_abandoned,
  sessions_fatal,
  sessions_killed,
  (select count(*) from pg_index i
    where not indisvalid
    and not exists ( /* leave out ones that are being actively rebuilt */
      select * from pg_locks l
      join pg_stat_activity a using (pid)
      where l.relation = i.indexrelid
      and a.state = 'active'
      and a.query ~* 'concurrently'
  )) as invalid_indexes
from
  pg_stat_database, pg_control_system()
where
  datname = current_database();
$sql$,
'{"prometheus_gauge_columns": ["numbackends", "postmaster_uptime_s", "checksum_last_failure_s"]}'
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs)
values (
'db_stats_aurora',
9.6,
$sql$
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  numbackends,
  xact_commit,
  xact_rollback,
  blks_read,
  blks_hit,
  tup_returned,
  tup_fetched,
  tup_inserted,
  tup_updated,
  tup_deleted,
  conflicts,
  temp_files,
  temp_bytes,
  deadlocks,
  blk_read_time,
  blk_write_time,
  extract(epoch from (now() - pg_postmaster_start_time()))::int8 as postmaster_uptime_s,
  case when pg_is_in_recovery() then 1 else 0 end as in_recovery_int
from
  pg_stat_database
where
  datname = current_database();
$sql$,
'{"prometheus_gauge_columns": ["numbackends", "postmaster_uptime_s"]}'
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs)
values (
'db_stats_aurora',
10,
$sql$
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  numbackends,
  xact_commit,
  xact_rollback,
  blks_read,
  blks_hit,
  tup_returned,
  tup_fetched,
  tup_inserted,
  tup_updated,
  tup_deleted,
  conflicts,
  temp_files,
  temp_bytes,
  deadlocks,
  blk_read_time,
  blk_write_time,
  extract(epoch from (now() - pg_postmaster_start_time()))::int8 as postmaster_uptime_s,
  case when pg_is_in_recovery() then 1 else 0 end as in_recovery_int,
  system_identifier::text as tag_sys_id
from
  pg_stat_database, pg_control_system()
where
  datname = current_database();
$sql$,
'{"prometheus_gauge_columns": ["numbackends", "postmaster_uptime_s"]}'
);

/* db_size */

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs)
values (
'db_size',
9.0,
$sql$
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  pg_database_size(current_database()) as size_b,
  (select sum(pg_total_relation_size(c.oid))::int8
   from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where nspname = 'pg_catalog' and relkind = 'r'
  ) as catalog_size_b;
$sql$,
'{"prometheus_all_gauge_columns": true}'
);

/* db_size_approx */

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs)
values (
'db_size_approx',
9.1,
$sql$
select /* pgwatch2_generated */
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  current_setting('block_size')::int8 * (
    select sum(relpages) from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where c.relpersistence != 't'
  ) as size_b,
  current_setting('block_size')::int8 * (
    select sum(c.relpages + coalesce(ct.relpages, 0) + coalesce(cti.relpages, 0))
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    left join pg_class ct on ct.oid = c.reltoastrelid
    left join pg_index ti on ti.indrelid = ct.oid
    left join pg_class cti on cti.oid = ti.indexrelid
    where nspname = 'pg_catalog'
    and (c.relkind = 'r'
      or c.relkind = 'i' and not c.relname ~ '^pg_toast')
  ) as catalog_size_b;
$sql$,
'{"prometheus_all_gauge_columns": true}'
);

/* index_stats */

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs)
values (
'index_stats',
9.0,
$sql$
/* NB! does not return all index stats but biggest, top scanned and biggest unused ones */
WITH q_locked_rels AS (
  select relation from pg_locks where mode = 'AccessExclusiveLock'
),
q_index_details AS (
  select
    sui.schemaname,
    sui.indexrelname,
    sui.relname,
    sui.indexrelid,
    coalesce(pg_relation_size(sui.indexrelid), 0) as index_size_b,
    sui.idx_scan,
    sui.idx_tup_read,
    sui.idx_tup_fetch,
    io.idx_blks_read,
    io.idx_blks_hit,
    i.indisvalid,
    i.indisprimary,
    i.indisunique
  from
    pg_stat_user_indexes sui
    join pg_statio_user_indexes io on io.indexrelid = sui.indexrelid
    join pg_index i on i.indexrelid = sui.indexrelid
  where not sui.schemaname like E'pg\\_temp%'
  and not exists (select * from q_locked_rels where relation = sui.relid or relation = sui.indexrelid)
),
q_top_indexes AS (
    /* biggest */
    select *
    from (
             select indexrelid
             from q_index_details
             where idx_scan > 1
             order by index_size_b desc
             limit 200
         ) x
    union
    /* most block traffic */
    select *
    from (
             select indexrelid
             from q_index_details
             order by coalesce(idx_blks_read, 0) + coalesce(idx_blks_hit, 0) desc
             limit 200
         ) y
    union
    /* most scans */
    select *
    from (
             select indexrelid
             from q_index_details
             order by idx_scan desc nulls last
             limit 200
         ) z
    union
    /* biggest unused non-constraint */
    select *
    from (
             select q.indexrelid
             from q_index_details q
             where idx_scan = 0
             and not (indisprimary or indisunique)
             order by index_size_b desc
             limit 200
         ) z
    union
    /* all invalid */
    select *
    from (
             select q.indexrelid
             from q_index_details q
             where not indisvalid
         ) zz
)
SELECT
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  schemaname::text as tag_schema,
  indexrelname::text as tag_index_name,
  quote_ident(schemaname)||'.'||quote_ident(indexrelname) as tag_index_full_name,
  relname::text as tag_table_name,
  quote_ident(schemaname)||'.'||quote_ident(relname) as tag_table_full_name,
  coalesce(idx_scan, 0) as idx_scan,
  coalesce(idx_tup_read, 0) as idx_tup_read,
  coalesce(idx_tup_fetch, 0) as idx_tup_fetch,
  coalesce(index_size_b, 0) as index_size_b,
  quote_ident(schemaname)||'.'||quote_ident(indexrelname) as index_full_name_val,
  md5(regexp_replace(regexp_replace(pg_get_indexdef(indexrelid),indexrelname,'X'), '^CREATE UNIQUE','CREATE')) as tag_index_def_hash,
  regexp_replace(regexp_replace(pg_get_indexdef(indexrelid),indexrelname,'X'), '^CREATE UNIQUE','CREATE') as index_def,
  case when not indisvalid then 1 else 0 end as is_invalid_int,
  case when indisprimary then 1 else 0 end as is_pk_int,
  case when indisunique then 1 else 0 end as is_uq_or_exc
FROM
  q_index_details id
WHERE
  indexrelid IN (select indexrelid from q_top_indexes)
ORDER BY
  id.schemaname, id.relname, id.indexrelname;
$sql$,
'{"prometheus_gauge_columns": ["index_size_b", "is_invalid_int", "is_pk_int"]}'
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs)
values (
'index_stats',
9.1,
$sql$
/* NB! does not return all index stats but biggest, top scanned and biggest unused ones */
WITH q_locked_rels AS (
  select relation from pg_locks where mode = 'AccessExclusiveLock'
),
q_index_details AS (
  select
    sui.schemaname,
    sui.indexrelname,
    sui.relname,
    sui.indexrelid,
    coalesce(pg_relation_size(sui.indexrelid), 0) as index_size_b,
    sui.idx_scan,
    sui.idx_tup_read,
    sui.idx_tup_fetch,
    io.idx_blks_read,
    io.idx_blks_hit,
    i.indisvalid,
    i.indisprimary,
    i.indisunique,
    i.indisexclusion
  from
    pg_stat_user_indexes sui
    join pg_statio_user_indexes io on io.indexrelid = sui.indexrelid
    join pg_index i on i.indexrelid = sui.indexrelid
  where not sui.schemaname like E'pg\\_temp%'
  and not exists (select * from q_locked_rels where relation = sui.relid or relation = sui.indexrelid)
),
q_top_indexes AS (
    /* biggest */
    select *
    from (
             select indexrelid
             from q_index_details
             where idx_scan > 1
             order by index_size_b desc
             limit 200
         ) x
    union
    /* most block traffic */
    select *
    from (
             select indexrelid
             from q_index_details
             order by coalesce(idx_blks_read, 0) + coalesce(idx_blks_hit, 0) desc
             limit 200
         ) y
    union
    /* most scans */
    select *
    from (
             select indexrelid
             from q_index_details
             order by idx_scan desc nulls last
             limit 200
         ) z
    union
    /* biggest unused non-constraint */
    select *
    from (
             select q.indexrelid
             from q_index_details q
             where idx_scan = 0
             and not (indisprimary or indisunique or indisexclusion)
             order by index_size_b desc
             limit 200
         ) z
    union
    /* all invalid */
    select *
    from (
             select q.indexrelid
             from q_index_details q
             where not indisvalid
         ) zz
)
SELECT
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  schemaname::text as tag_schema,
  indexrelname::text as tag_index_name,
  quote_ident(schemaname)||'.'||quote_ident(indexrelname) as tag_index_full_name,
  relname::text as tag_table_name,
  quote_ident(schemaname)||'.'||quote_ident(relname) as tag_table_full_name,
  coalesce(idx_scan, 0) as idx_scan,
  coalesce(idx_tup_read, 0) as idx_tup_read,
  coalesce(idx_tup_fetch, 0) as idx_tup_fetch,
  coalesce(index_size_b, 0) as index_size_b,
  quote_ident(schemaname)||'.'||quote_ident(indexrelname) as index_full_name_val,
  md5(regexp_replace(regexp_replace(pg_get_indexdef(indexrelid),indexrelname,'X'), '^CREATE UNIQUE','CREATE')) as tag_index_def_hash,
  regexp_replace(regexp_replace(pg_get_indexdef(indexrelid),indexrelname,'X'), '^CREATE UNIQUE','CREATE') as index_def,
  case when not indisvalid then 1 else 0 end as is_invalid_int,
  case when indisprimary then 1 else 0 end as is_pk_int,
  case when indisunique or indisexclusion then 1 else 0 end as is_uq_or_exc
FROM
  q_index_details id
WHERE
  indexrelid IN (select indexrelid from q_top_indexes)
ORDER BY
  id.schemaname, id.relname, id.indexrelname;
$sql$,
'{"prometheus_gauge_columns": ["index_size_b", "is_invalid_int", "is_pk_int"]}'
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs)
values (
'index_stats',
10,
$sql$
/* NB! does not return all index stats but biggest, top scanned and biggest unused ones */
WITH q_locked_rels AS (
  select relation from pg_locks where mode = 'AccessExclusiveLock'
),
q_index_details AS (
  select
    sui.schemaname,
    sui.indexrelname,
    sui.relname,
    sui.indexrelid,
    coalesce(pg_relation_size(sui.indexrelid), 0) as index_size_b,
    sui.idx_scan,
    sui.idx_tup_read,
    sui.idx_tup_fetch,
    io.idx_blks_read,
    io.idx_blks_hit,
    i.indisvalid,
    i.indisprimary,
    i.indisunique,
    i.indisexclusion
  from
    pg_stat_user_indexes sui
    join pg_statio_user_indexes io on io.indexrelid = sui.indexrelid
    join pg_index i on i.indexrelid = sui.indexrelid
  where not sui.schemaname like any (array [E'pg\\_temp%', E'\\_timescaledb%'])
  and not exists (select * from q_locked_rels where relation = sui.relid or relation = sui.indexrelid)
),
q_top_indexes AS (
    /* biggest */
    select *
    from (
             select indexrelid
             from q_index_details
             where idx_scan > 1
             order by index_size_b desc
             limit 200
         ) x
    union
    /* most block traffic */
    select *
    from (
             select indexrelid
             from q_index_details
             order by coalesce(idx_blks_read, 0) + coalesce(idx_blks_hit, 0) desc
             limit 200
         ) y
    union
    /* most scans */
    select *
    from (
             select indexrelid
             from q_index_details
             order by idx_scan desc nulls last
             limit 200
         ) z
    union
    /* biggest unused non-constraint */
    select *
    from (
             select q.indexrelid
             from q_index_details q
             where idx_scan = 0
             and not (indisprimary or indisunique or indisexclusion)
             order by index_size_b desc
             limit 200
         ) z
    union
    /* all invalid */
    select *
    from (
             select q.indexrelid
             from q_index_details q
             where not indisvalid
         ) zz
)
SELECT
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  schemaname::text as tag_schema,
  indexrelname::text as tag_index_name,
  quote_ident(schemaname)||'.'||quote_ident(indexrelname) as tag_index_full_name,
  relname::text as tag_table_name,
  quote_ident(schemaname)||'.'||quote_ident(relname) as tag_table_full_name,
  coalesce(idx_scan, 0) as idx_scan,
  coalesce(idx_tup_read, 0) as idx_tup_read,
  coalesce(idx_tup_fetch, 0) as idx_tup_fetch,
  coalesce(index_size_b, 0) as index_size_b,
  quote_ident(schemaname)||'.'||quote_ident(indexrelname) as index_full_name_val,
  md5(regexp_replace(regexp_replace(pg_get_indexdef(indexrelid),indexrelname,'X'), '^CREATE UNIQUE','CREATE')) as tag_index_def_hash,
  regexp_replace(regexp_replace(pg_get_indexdef(indexrelid),indexrelname,'X'), '^CREATE UNIQUE','CREATE') as index_def,
  case when not indisvalid then 1 else 0 end as is_invalid_int,
  case when indisprimary then 1 else 0 end as is_pk_int,
  case when indisunique or indisexclusion then 1 else 0 end as is_uq_or_exc,
  system_identifier::text as tag_sys_id
FROM
  q_index_details id
  JOIN
  pg_control_system() ON true
WHERE
  indexrelid IN (select indexrelid from q_top_indexes)
ORDER BY
  id.schemaname, id.relname, id.indexrelname;
$sql$,
'{"prometheus_gauge_columns": ["index_size_b", "is_invalid_int", "is_pk_int"]}'
);


insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs)
values (
'index_stats',
16,
$sql$
/* NB! does not return all index stats but biggest, top scanned and biggest unused ones */
WITH q_locked_rels AS ( /* pgwatch2_generated */
  select relation from pg_locks where mode = 'AccessExclusiveLock'
),
q_index_details AS (
  select
    sui.schemaname,
    sui.indexrelname,
    sui.relname,
    sui.indexrelid,
    coalesce(pg_relation_size(sui.indexrelid), 0) as index_size_b,
    sui.idx_scan,
    sui.idx_tup_read,
    sui.idx_tup_fetch,
    io.idx_blks_read,
    io.idx_blks_hit,
    i.indisvalid,
    i.indisprimary,
    i.indisunique,
    i.indisexclusion,
    extract(epoch from now() - last_idx_scan)::int as last_idx_scan_s
  from
    pg_stat_user_indexes sui
    join pg_statio_user_indexes io on io.indexrelid = sui.indexrelid
    join pg_index i on i.indexrelid = sui.indexrelid
  where not sui.schemaname like any (array [E'pg\\_temp%', E'\\_timescaledb%'])
  and not exists (select * from q_locked_rels where relation = sui.relid or relation = sui.indexrelid)
),
q_top_indexes AS (
    /* biggest */
    select *
    from (
             select indexrelid
             from q_index_details
             where idx_scan > 1
             order by index_size_b desc
             limit 200
         ) x
    union
    /* most block traffic */
    select *
    from (
             select indexrelid
             from q_index_details
             order by coalesce(idx_blks_read, 0) + coalesce(idx_blks_hit, 0) desc
             limit 200
         ) y
    union
    /* most scans */
    select *
    from (
             select indexrelid
             from q_index_details
             order by idx_scan desc nulls last
             limit 200
         ) z
    union
    /* biggest unused non-constraint */
    select *
    from (
             select q.indexrelid
             from q_index_details q
             where idx_scan = 0
             and not (indisprimary or indisunique or indisexclusion)
             order by index_size_b desc
             limit 200
         ) z
    union
    /* all invalid */
    select *
    from (
             select q.indexrelid
             from q_index_details q
             where not indisvalid
         ) zz
)
SELECT
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  schemaname::text as tag_schema,
  indexrelname::text as tag_index_name,
  quote_ident(schemaname)||'.'||quote_ident(indexrelname) as tag_index_full_name,
  relname::text as tag_table_name,
  quote_ident(schemaname)||'.'||quote_ident(relname) as tag_table_full_name,
  coalesce(idx_scan, 0) as idx_scan,
  coalesce(idx_tup_read, 0) as idx_tup_read,
  coalesce(idx_tup_fetch, 0) as idx_tup_fetch,
  coalesce(index_size_b, 0) as index_size_b,
  quote_ident(schemaname)||'.'||quote_ident(indexrelname) as index_full_name_val,
  md5(regexp_replace(regexp_replace(pg_get_indexdef(indexrelid),indexrelname,'X'), '^CREATE UNIQUE','CREATE')) as tag_index_def_hash,
  regexp_replace(regexp_replace(pg_get_indexdef(indexrelid),indexrelname,'X'), '^CREATE UNIQUE','CREATE') as index_def,
  case when not indisvalid then 1 else 0 end as is_invalid_int,
  case when indisprimary then 1 else 0 end as is_pk_int,
  case when indisunique or indisexclusion then 1 else 0 end as is_uq_or_exc,
  system_identifier::text as tag_sys_id,
  last_idx_scan_s
FROM
  q_index_details id
  JOIN
  pg_control_system() ON true
WHERE
  indexrelid IN (select indexrelid from q_top_indexes)
ORDER BY
  id.schemaname, id.relname, id.indexrelname;
$sql$,
'{"prometheus_gauge_columns": ["index_size_b", "is_invalid_int", "is_pk_int"]}'
);

/* kpi */

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs, m_sql_su)
values (
'kpi',
9.0,
$sql$
WITH q_stat_tables AS (
  SELECT * FROM pg_stat_user_tables t
  JOIN pg_class c ON c.oid = t.relid
  WHERE NOT schemaname LIKE E'pg\\_temp%'
  AND c.relpages > (1e7 / 8)    -- >10MB
),
q_stat_activity AS (
  SELECT * FROM get_stat_activity()
)
SELECT
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  numbackends - 1 as numbackends,
  (select count(*) from q_stat_activity where not current_query in ('<IDLE>', '<IDLE> in transaction')) AS active_backends,
  (select count(*) from q_stat_activity where waiting) AS blocked_backends,
  (select round(extract(epoch from now()) - extract(epoch from (select xact_start from q_stat_activity
    where datid = d.datid and not current_query like 'autovacuum:%' order by xact_start limit 1))))::int AS kpi_oldest_tx_s,
  xact_commit + xact_rollback AS tps,
  xact_commit,
  xact_rollback,
  blks_read,
  blks_hit,
  (select sum(seq_scan) from q_stat_tables)::int8 AS seq_scans_on_tbls_gt_10mb,
  tup_inserted,
  tup_updated,
  tup_deleted,
  (select sum(calls) from pg_stat_user_functions where not schemaname like any(array[E'pg\\_%', 'information_schema']))::int8 AS sproc_calls,
  extract(epoch from (now() - pg_postmaster_start_time()))::int8 as postmaster_uptime_s
FROM
  pg_stat_database d
WHERE
  datname = current_database();
$sql$,
'{"prometheus_gauge_columns": ["numbackends", "active_backends", "blocked_backends", "kpi_oldest_tx_s"]}',
$sql$
WITH q_stat_tables AS (
  SELECT * FROM pg_stat_user_tables t
  JOIN pg_class c ON c.oid = t.relid
  WHERE NOT schemaname LIKE E'pg\\_temp%'
  AND c.relpages > (1e7 / 8)    -- >10MB
),
q_stat_activity AS (
  SELECT * FROM pg_stat_activity WHERE procpid != pg_backend_pid() AND datname = current_database()
)
SELECT
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  numbackends - 1 as numbackends,
  (select count(*) from q_stat_activity where not current_query in ('<IDLE>', '<IDLE> in transaction')) AS active_backends,
  (select count(*) from q_stat_activity where waiting) AS blocked_backends,
  (select round(extract(epoch from now()) - extract(epoch from (select xact_start from q_stat_activity
    where datid = d.datid and not current_query like 'autovacuum:%' order by xact_start limit 1))))::int AS kpi_oldest_tx_s,
  xact_commit + xact_rollback AS tps,
  xact_commit,
  xact_rollback,
  blks_read,
  blks_hit,
  (select sum(seq_scan) from q_stat_tables)::int8 AS seq_scans_on_tbls_gt_10mb,
  tup_inserted,
  tup_updated,
  tup_deleted,
  (select sum(calls) from pg_stat_user_functions where not schemaname like any(array[E'pg\\_%', 'information_schema']))::int8 AS sproc_calls,
  extract(epoch from (now() - pg_postmaster_start_time()))::int8 as postmaster_uptime_s
FROM
  pg_stat_database d
WHERE
  datname = current_database();
$sql$
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs, m_sql_su)
values (
'kpi',
9.2,
$sql$
WITH q_stat_tables AS (
  SELECT * FROM pg_stat_user_tables t
  JOIN pg_class c ON c.oid = t.relid
  WHERE NOT schemaname LIKE E'pg\\_temp%'
  AND c.relpages > (1e7 / 8)    -- >10MB
),
q_stat_activity AS (
  SELECT * FROM get_stat_activity()
)
SELECT
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  case
      when pg_is_in_recovery() = false then
          pg_xlog_location_diff(pg_current_xlog_location(), '0/0')::int8
      else
          pg_xlog_location_diff(pg_last_xlog_replay_location(), '0/0')::int8
      end as wal_location_b,
  numbackends - 1 as numbackends,
  (select count(1) from q_stat_activity where state = 'active') AS active_backends,
  (select count(1) from q_stat_activity where waiting) AS blocked_backends,
  (select round(extract(epoch from now()) - extract(epoch from (select xact_start from q_stat_activity
    where datid = d.datid and not query like 'autovacuum:%' order by xact_start limit 1))))::int AS kpi_oldest_tx_s,
  xact_commit + xact_rollback AS tps,
  xact_commit,
  xact_rollback,
  blks_read,
  blks_hit,
  temp_bytes,
  (select sum(seq_scan) from q_stat_tables)::int8 AS seq_scans_on_tbls_gt_10mb,
  tup_inserted,
  tup_updated,
  tup_deleted,
  (select sum(calls) from pg_stat_user_functions where not schemaname like any(array[E'pg\\_%', 'information_schema']))::int8 AS sproc_calls,
  blk_read_time,
  blk_write_time,
  deadlocks,
  case when pg_is_in_recovery() then 1 else 0 end as in_recovery_int,
  extract(epoch from (now() - pg_postmaster_start_time()))::int8 as postmaster_uptime_s
FROM
  pg_stat_database d
WHERE
  datname = current_database();
$sql$,
'{"prometheus_gauge_columns": ["numbackends", "active_backends", "blocked_backends", "kpi_oldest_tx_s"]}',
$sql$
WITH q_stat_tables AS (
    SELECT * FROM pg_stat_user_tables t
                      JOIN pg_class c ON c.oid = t.relid
    WHERE NOT schemaname LIKE E'pg\\_temp%'
      AND c.relpages > (1e7 / 8)    -- >10MB
),
     q_stat_activity AS (
         SELECT * FROM pg_stat_activity
         WHERE datname = current_database() AND pid != pg_backend_pid()
     )
SELECT
    (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  case
      when pg_is_in_recovery() = false then
          pg_xlog_location_diff(pg_current_xlog_location(), '0/0')::int8
      else
          pg_xlog_location_diff(pg_last_xlog_replay_location(), '0/0')::int8
      end as wal_location_b,
    numbackends - 1 as numbackends,
    (select count(1) from q_stat_activity where state = 'active') AS active_backends,
    (select count(1) from q_stat_activity where waiting) AS blocked_backends,
    (select round(extract(epoch from now()) - extract(epoch from (select xact_start from q_stat_activity
                                                                  where datid = d.datid and not query like 'autovacuum:%' order by xact_start limit 1))))::int AS kpi_oldest_tx_s,
    xact_commit + xact_rollback AS tps,
    xact_commit,
    xact_rollback,
    blks_read,
    blks_hit,
    temp_bytes,
    (select sum(seq_scan) from q_stat_tables)::int8 AS seq_scans_on_tbls_gt_10mb,
    tup_inserted,
    tup_updated,
    tup_deleted,
    (select sum(calls) from pg_stat_user_functions where not schemaname like any(array[E'pg\\_%', 'information_schema']))::int8 AS sproc_calls,
    blk_read_time,
    blk_write_time,
    deadlocks,
    case when pg_is_in_recovery() then 1 else 0 end as in_recovery_int,
    extract(epoch from (now() - pg_postmaster_start_time()))::int8 as postmaster_uptime_s
FROM
    pg_stat_database d
WHERE
    datname = current_database();
$sql$
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs, m_sql_su)
values (
'kpi',
9.6,
$sql$
WITH q_stat_tables AS (
  SELECT * FROM pg_stat_user_tables t
  JOIN pg_class c ON c.oid = t.relid
  WHERE NOT schemaname LIKE E'pg\\_temp%'
  AND c.relpages > (1e7 / 8)    -- >10MB
),
q_stat_activity AS (
  SELECT * FROM get_stat_activity()
)
SELECT
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  case
    when pg_is_in_recovery() = false then
      pg_xlog_location_diff(pg_current_xlog_location(), '0/0')::int8
    else
      pg_xlog_location_diff(pg_last_xlog_replay_location(), '0/0')::int8
    end as wal_location_b,
  numbackends - 1 as numbackends,
  (select count(1) from q_stat_activity where state = 'active') AS active_backends,
  (select count(1) from q_stat_activity where wait_event_type is not null) AS blocked_backends,
  (select round(extract(epoch from now()) - extract(epoch from (select xact_start from q_stat_activity
    where datid = d.datid and not query like 'autovacuum:%' order by xact_start limit 1))))::int AS kpi_oldest_tx_s,
  xact_commit + xact_rollback AS tps,
  xact_commit,
  xact_rollback,
  blks_read,
  blks_hit,
  temp_bytes,
  (select sum(seq_scan) from q_stat_tables)::int8 AS seq_scans_on_tbls_gt_10mb,
  tup_inserted,
  tup_updated,
  tup_deleted,
  (select sum(calls) from pg_stat_user_functions where not schemaname like any(array[E'pg\\_%', 'information_schema']))::int8 AS sproc_calls,
  blk_read_time,
  blk_write_time,
  deadlocks,
  case when pg_is_in_recovery() then 1 else 0 end as in_recovery_int,
  extract(epoch from (now() - pg_postmaster_start_time()))::int8 as postmaster_uptime_s
FROM
  pg_stat_database d
WHERE
  datname = current_database();
$sql$,
'{"prometheus_gauge_columns": ["numbackends", "active_backends", "blocked_backends", "kpi_oldest_tx_s"]}',
$sql$
WITH q_stat_tables AS (
  SELECT * FROM pg_stat_user_tables t
  JOIN pg_class c ON c.oid = t.relid
  WHERE NOT schemaname LIKE E'pg\\_temp%'
  AND c.relpages > (1e7 / 8)    -- >10MB
),
q_stat_activity AS (
    SELECT * FROM pg_stat_activity
    WHERE datname = current_database() AND pid != pg_backend_pid()
)
SELECT
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  case
    when pg_is_in_recovery() = false then
      pg_xlog_location_diff(pg_current_xlog_location(), '0/0')::int8
    else
      pg_xlog_location_diff(pg_last_xlog_replay_location(), '0/0')::int8
    end as xlog_location_b,
  numbackends - 1 as numbackends,
  (select count(*) from q_stat_activity where state in ('active', 'idle in transaction')) AS active_backends,
  (select count(*) from q_stat_activity where wait_event_type in ('LWLockNamed', 'Lock', 'BufferPin')) AS blocked_backends,
  (select round(extract(epoch from now()) - extract(epoch from (select xact_start from q_stat_activity
    where datid = d.datid and not query like 'autovacuum:%' order by xact_start limit 1))))::int AS kpi_oldest_tx_s,
  xact_commit + xact_rollback AS tps,
  xact_commit,
  xact_rollback,
  blks_read,
  blks_hit,
  temp_bytes,
  (select sum(seq_scan) from q_stat_tables)::int8 AS seq_scans_on_tbls_gt_10mb,
  tup_inserted,
  tup_updated,
  tup_deleted,
  (select sum(calls) from pg_stat_user_functions where not schemaname like any(array[E'pg\\_%', 'information_schema']))::int8 AS sproc_calls,
  blk_read_time,
  blk_write_time,
  deadlocks,
  case when pg_is_in_recovery() then 1 else 0 end as in_recovery_int,
  extract(epoch from (now() - pg_postmaster_start_time()))::int8 as postmaster_uptime_s
FROM
  pg_stat_database d
WHERE
  datname = current_database();
$sql$
);

/* kpi */

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs, m_sql_su)
values (
'kpi',
10,
$sql$
WITH q_stat_tables AS (
  SELECT * FROM pg_stat_user_tables t
  JOIN pg_class c ON c.oid = t.relid
  WHERE NOT schemaname LIKE E'pg\\_temp%'
  AND c.relpages > (1e7 / 8)    -- >10MB
),
q_stat_activity AS (
  SELECT * FROM get_stat_activity()
)
SELECT
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  case
      when pg_is_in_recovery() = false then
          pg_wal_lsn_diff(pg_current_wal_lsn(), '0/0')::int8
      else
          pg_wal_lsn_diff(pg_last_wal_replay_lsn(), '0/0')::int8
      end as wal_location_b,
  numbackends - 1 as numbackends,
  (select count(1) from q_stat_activity where state = 'active') AS active_backends,
  (select count(1) from q_stat_activity where wait_event_type is not null) AS blocked_backends,
  (select round(extract(epoch from now()) - extract(epoch from (select xact_start from q_stat_activity
    where datid = d.datid and not query like 'autovacuum:%' order by xact_start limit 1))))::int AS kpi_oldest_tx_s,
  xact_commit + xact_rollback AS tps,
  xact_commit,
  xact_rollback,
  blks_read,
  blks_hit,
  temp_bytes,
  (select sum(seq_scan) from q_stat_tables)::int8 AS seq_scans_on_tbls_gt_10mb,
  tup_inserted,
  tup_updated,
  tup_deleted,
  (select sum(calls) from pg_stat_user_functions where not schemaname like any(array[E'pg\\_%', 'information_schema']))::int8 AS sproc_calls,
  blk_read_time,
  blk_write_time,
  deadlocks,
  case when pg_is_in_recovery() then 1 else 0 end as in_recovery_int,
  extract(epoch from (now() - pg_postmaster_start_time()))::int8 as postmaster_uptime_s
FROM
  pg_stat_database d
WHERE
  datname = current_database();
$sql$,
'{"prometheus_gauge_columns": ["numbackends", "active_backends", "blocked_backends", "kpi_oldest_tx_s"]}',
$sql$
WITH q_stat_tables AS (
  SELECT * FROM pg_stat_user_tables t
  JOIN pg_class c ON c.oid = t.relid
  WHERE NOT schemaname LIKE E'pg\\_temp%'
  AND c.relpages > (1e7 / 8)    -- >10MB
),
q_stat_activity AS (
    SELECT * FROM pg_stat_activity
    WHERE datname = current_database() AND pid != pg_backend_pid()
)
SELECT
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  case
      when pg_is_in_recovery() = false then
          pg_wal_lsn_diff(pg_current_wal_lsn(), '0/0')::int8
      else
          pg_wal_lsn_diff(pg_last_wal_replay_lsn(), '0/0')::int8
      end as wal_location_b,
  numbackends - 1 as numbackends,
  (select count(*) from q_stat_activity where state in ('active', 'idle in transaction')) AS active_backends,
  (select count(*) from q_stat_activity where wait_event_type in ('LWLock', 'Lock', 'BufferPin')) AS blocked_backends,
  (select round(extract(epoch from now()) - extract(epoch from (select xact_start from q_stat_activity
    where datid = d.datid and not query like 'autovacuum:%' order by xact_start limit 1))))::int AS kpi_oldest_tx_s,
  xact_commit + xact_rollback AS tps,
  xact_commit,
  xact_rollback,
  blks_read,
  blks_hit,
  temp_bytes,
  (select sum(seq_scan) from q_stat_tables)::int8 AS seq_scans_on_tbls_gt_10mb,
  tup_inserted,
  tup_updated,
  tup_deleted,
  (select sum(calls) from pg_stat_user_functions where not schemaname like any(array[E'pg\\_%', 'information_schema']))::int8 AS sproc_calls,
  blk_read_time,
  blk_write_time,
  deadlocks,
  case when pg_is_in_recovery() then 1 else 0 end as in_recovery_int,
  extract(epoch from (now() - pg_postmaster_start_time()))::int8 as postmaster_uptime_s
FROM
  pg_stat_database d
WHERE
  datname = current_database();
$sql$
);


/* replication */

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs, m_sql_su)
values (
'replication',
9.2,
$sql$
SELECT
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  application_name as tag_application_name,
  concat(coalesce(client_addr::text, client_hostname), '_', client_port::text) as tag_client_info,
  coalesce(pg_xlog_location_diff(case when pg_is_in_recovery() then pg_last_xlog_receive_location() else pg_current_xlog_location() end, write_location)::int8, 0) as write_lag_b,
  coalesce(pg_xlog_location_diff(case when pg_is_in_recovery() then pg_last_xlog_receive_location() else pg_current_xlog_location() end, flush_location)::int8, 0) as flush_lag_b,
  coalesce(pg_xlog_location_diff(case when pg_is_in_recovery() then pg_last_xlog_receive_location() else pg_current_xlog_location() end, replay_location)::int8, 0) as replay_lag_b,
  state,
  sync_state,
  case when sync_state in ('sync', 'quorum') then 1 else 0 end as is_sync_int,
  case when pg_is_in_recovery() then 1 else 0 end as in_recovery_int
from
  get_stat_replication()
where
  coalesce(application_name, '') not in ('pg_basebackup', 'pg_rewind');
$sql$,
'{"prometheus_all_gauge_columns": true}',
$sql$
SELECT
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  application_name as tag_application_name,
  concat(coalesce(client_addr::text, client_hostname), '_', client_port::text) as tag_client_info,
  coalesce(pg_xlog_location_diff(case when pg_is_in_recovery() then pg_last_xlog_receive_location() else pg_current_xlog_location() end, write_location)::int8, 0) as write_lag_b,
  coalesce(pg_xlog_location_diff(case when pg_is_in_recovery() then pg_last_xlog_receive_location() else pg_current_xlog_location() end, flush_location)::int8, 0) as flush_lag_b,
  coalesce(pg_xlog_location_diff(case when pg_is_in_recovery() then pg_last_xlog_receive_location() else pg_current_xlog_location() end, replay_location)::int8, 0) as replay_lag_b,
  state,
  sync_state,
  case when sync_state in ('sync', 'quorum') then 1 else 0 end as is_sync_int,
  case when pg_is_in_recovery() then 1 else 0 end as in_recovery_int
from
  pg_stat_replication
where
  coalesce(application_name, '') not in ('pg_basebackup', 'pg_rewind');
$sql$
);

/* replication */

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs)
values (
'replication',
10,
$sql$
SELECT
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  application_name as tag_application_name,
  concat(coalesce(client_addr::text, client_hostname), '_', client_port::text) as tag_client_info,
  coalesce(pg_wal_lsn_diff(case when pg_is_in_recovery() then pg_last_wal_receive_lsn() else pg_current_wal_lsn() end, sent_lsn)::int8, 0) as sent_lag_b,
  coalesce(pg_wal_lsn_diff(case when pg_is_in_recovery() then pg_last_wal_receive_lsn() else pg_current_wal_lsn() end, write_lsn)::int8, 0) as write_lag_b,
  coalesce(pg_wal_lsn_diff(case when pg_is_in_recovery() then pg_last_wal_receive_lsn() else pg_current_wal_lsn() end, flush_lsn)::int8, 0) as flush_lag_b,
  coalesce(pg_wal_lsn_diff(case when pg_is_in_recovery() then pg_last_wal_receive_lsn() else pg_current_wal_lsn() end, replay_lsn)::int8, 0) as replay_lag_b,
  (extract(epoch from write_lag) * 1000)::int8 as write_lag_ms,
  (extract(epoch from flush_lag) * 1000)::int8 as flush_lag_ms,
  (extract(epoch from replay_lag) * 1000)::int8 as replay_lag_ms,
  state,
  sync_state,
  case when sync_state in ('sync', 'quorum') then 1 else 0 end as is_sync_int,
  case when pg_is_in_recovery() then 1 else 0 end as in_recovery_int
from
  /* NB! when the query fails, grant "pg_monitor" system role (exposing all stats) to the monitoring user
     or create specifically the "get_stat_replication" helper and use that instead of pg_stat_replication
  */
  pg_stat_replication
where
  coalesce(application_name, '') not in ('pg_basebackup', 'pg_rewind');
$sql$,
'{"prometheus_all_gauge_columns": true}'
);


/* sproc_stats */

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql)
values (
'sproc_stats',
9.0,
$sql$
SELECT
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  schemaname::text AS tag_schema,
  funcname::text  AS tag_function_name,
  quote_ident(schemaname)||'.'||quote_ident(funcname) as tag_function_full_name,
  p.oid::text as tag_oid, -- for overloaded funcs
  calls as sp_calls,
  self_time,
  total_time
FROM
  pg_stat_user_functions f
  JOIN
  pg_proc p ON p.oid = f.funcid
ORDER BY
  total_time DESC
LIMIT
  300;
$sql$
);

/* table_io_stats */

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql)
values (
'table_io_stats',
9.0,
$sql$
SELECT
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  schemaname::text as tag_schema,
  relname::text as tag_table_name,
  quote_ident(schemaname)||'.'||quote_ident(relname) as tag_table_full_name,
  heap_blks_read,
  heap_blks_hit,
  idx_blks_read,
  idx_blks_hit,
  toast_blks_read,
  toast_blks_hit,
  tidx_blks_read,
  tidx_blks_hit
FROM
  pg_statio_user_tables
WHERE
  NOT schemaname LIKE E'pg\\_temp%'
  AND (heap_blks_read > 0 OR heap_blks_hit > 0 OR idx_blks_read > 0 OR idx_blks_hit > 0 OR tidx_blks_read > 0 OR tidx_blks_hit > 0)
ORDER BY
  coalesce(heap_blks_read, 0) +
  coalesce(heap_blks_hit, 0) +
  coalesce(idx_blks_read, 0) +
  coalesce(idx_blks_hit, 0) +
  coalesce(toast_blks_read, 0) +
  coalesce(toast_blks_hit, 0) +
  coalesce(tidx_blks_read, 0) +
  coalesce(tidx_blks_hit, 0)
  DESC LIMIT 300;
$sql$
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql)
values (
'table_io_stats',
10,
$sql$
select * from (
                  with recursive
                      q_root_part as (
                            select c.oid,
                                   c.relkind,
                                   n.nspname root_schema,
                                   c.relname root_relname
                            from pg_class c
                                     join pg_namespace n on n.oid = c.relnamespace
                            where relkind in ('p', 'r')
                              and relpersistence != 't'
                              and not n.nspname like any (array[E'pg\\_%', 'information_schema', E'\\_timescaledb%'])
                              and not exists(select * from pg_inherits where inhrelid = c.oid)
                              and exists(select * from pg_inherits where inhparent = c.oid)
                      ),
                      q_parts (relid, relkind, level, root) as (
                          select oid, relkind, 1, oid
                          from q_root_part
                          union all
                          select inhrelid, c.relkind, level + 1, q.root
                          from pg_inherits i
                                   join q_parts q on inhparent = q.relid
                                   join pg_class c on c.oid = i.inhrelid
                      ),
                      q_tstats as (
                          SELECT (extract(epoch from now()) * 1e9)::int8                as epoch_ns,
                                 relid,
                                 schemaname::text                                       as tag_schema,
                                 relname::text                                          as tag_table_name,
                                 quote_ident(schemaname) || '.' || quote_ident(relname) as tag_table_full_name,
                                 heap_blks_read,
                                 heap_blks_hit,
                                 idx_blks_read,
                                 idx_blks_hit,
                                 toast_blks_read,
                                 toast_blks_hit,
                                 tidx_blks_read,
                                 tidx_blks_hit
                          FROM pg_statio_user_tables
                          WHERE NOT schemaname LIKE E'pg\\_temp%'
                            AND (heap_blks_read > 0 OR heap_blks_hit > 0 OR idx_blks_read > 0 OR idx_blks_hit > 0 OR
                                 tidx_blks_read > 0 OR
                                 tidx_blks_hit > 0)
                      )
                  select epoch_ns,
                         tag_schema,
                         tag_table_name,
                         tag_table_full_name,
                         0 as is_part_root,
                         heap_blks_read,
                         heap_blks_hit,
                         idx_blks_read,
                         idx_blks_hit,
                         toast_blks_read,
                         toast_blks_hit,
                         tidx_blks_read,
                         tidx_blks_hit
                  from q_tstats
                  where not tag_schema like E'\\_timescaledb%'
                  and not exists (select * from q_root_part where oid = q_tstats.relid)

                  union all

                  select *
                  from (
                           select epoch_ns,
                                  quote_ident(qr.root_schema)                                        as tag_schema,
                                  quote_ident(qr.root_relname)                                       as tag_table_name,
                                  quote_ident(qr.root_schema) || '.' || quote_ident(qr.root_relname) as tag_table_full_name,
                                  1                                                                  as is_part_root,
                                  sum(heap_blks_read)::int8,
                                  sum(heap_blks_hit)::int8,
                                  sum(idx_blks_read)::int8,
                                  sum(idx_blks_hit)::int8,
                                  sum(toast_blks_read)::int8,
                                  sum(toast_blks_hit)::int8,
                                  sum(tidx_blks_read)::int8,
                                  sum(tidx_blks_hit)::int8
                           from q_tstats ts
                                    join q_parts qp on qp.relid = ts.relid
                                    join q_root_part qr on qr.oid = qp.root
                           group by 1, 2, 3, 4
                       ) x
              ) y
order by
  coalesce(heap_blks_read, 0) +
  coalesce(heap_blks_hit, 0) +
  coalesce(idx_blks_read, 0) +
  coalesce(idx_blks_hit, 0) +
  coalesce(toast_blks_read, 0) +
  coalesce(toast_blks_hit, 0) +
  coalesce(tidx_blks_read, 0) +
  coalesce(tidx_blks_hit, 0)
  desc limit 300;
$sql$
);

/* table_stats */

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs, m_master_only)
values (
'table_stats',
9.0,
$sql$
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  quote_ident(schemaname) as tag_schema,
  quote_ident(ut.relname) as tag_table_name,
  quote_ident(schemaname)||'.'||quote_ident(ut.relname) as tag_table_full_name,
  pg_table_size(relid) as table_size_b,
  abs(greatest(ceil(log((pg_table_size(relid)+1) / 10^6)), 0))::text as tag_table_size_cardinality_mb, -- i.e. 0=<1MB, 1=<10MB, 2=<100MB,..
  pg_total_relation_size(relid) as total_relation_size_b,
  case when reltoastrelid != 0 then pg_total_relation_size(reltoastrelid) else 0::int8 end as toast_size_b,
  (extract(epoch from now() - greatest(last_vacuum, last_autovacuum)))::int8 as seconds_since_last_vacuum,
  (extract(epoch from now() - greatest(last_analyze, last_autoanalyze)))::int8 as seconds_since_last_analyze,
  case when 'autovacuum_enabled=off' = ANY(c.reloptions) then 1 else 0 end as no_autovacuum,
  seq_scan,
  seq_tup_read,
  coalesce(idx_scan, 0) as idx_scan,
  coalesce(idx_tup_fetch, 0) as idx_tup_fetch,
  n_tup_ins,
  n_tup_upd,
  n_tup_del,
  n_tup_hot_upd,
  n_live_tup,
  n_dead_tup,
  age(relfrozenxid) as tx_freeze_age
from
  pg_stat_user_tables ut
  join
  pg_class c on c.oid = ut.relid
where
  -- leaving out fully locked tables as pg_relation_size also wants a lock and would wait
  not exists (select 1 from pg_locks where relation = relid and mode = 'AccessExclusiveLock')
  and not relistemp -- and temp tables
order by table_size_b desc nulls last limit 300;
$sql$,
'{"prometheus_gauge_columns": ["table_size_b", "total_relation_size_b", "toast_size_b", "seconds_since_last_vacuum", "seconds_since_last_analyze", "n_live_tup", "n_dead_tup"]}',
true
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs, m_standby_only)
values (
'table_stats',
9.0,
$sql$
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  quote_ident(schemaname) as tag_schema,
  quote_ident(ut.relname) as tag_table_name,
  quote_ident(schemaname)||'.'||quote_ident(ut.relname) as tag_table_full_name,
  pg_table_size(relid) as table_size_b,
  abs(greatest(ceil(log((pg_table_size(relid)+1) / 10^6)), 0))::text as tag_table_size_cardinality_mb, -- i.e. 0=<1MB, 1=<10MB, 2=<100MB,..
  pg_total_relation_size(relid) as total_relation_size_b,
  case when reltoastrelid != 0 then pg_total_relation_size(reltoastrelid) else 0::int8 end as toast_size_b,
  (extract(epoch from now() - greatest(last_vacuum, last_autovacuum)))::int8 as seconds_since_last_vacuum,
  (extract(epoch from now() - greatest(last_analyze, last_autoanalyze)))::int8 as seconds_since_last_analyze,
  case when 'autovacuum_enabled=off' = ANY(c.reloptions) then 1 else 0 end as no_autovacuum,
  seq_scan,
  seq_tup_read,
  coalesce(idx_scan, 0) as idx_scan,
  coalesce(idx_tup_fetch, 0) as idx_tup_fetch,
  n_tup_ins,
  n_tup_upd,
  n_tup_del,
  n_tup_hot_upd,
  n_live_tup,
  n_dead_tup
from
  pg_stat_user_tables ut
  join
  pg_class c on c.oid = ut.relid
where
  -- leaving out fully locked tables as pg_relation_size also wants a lock and would wait
  not exists (select 1 from pg_locks where relation = relid and mode = 'AccessExclusiveLock')
  and not relistemp -- and temp tables
order by table_size_b desc nulls last limit 300;
$sql$,
'{"prometheus_gauge_columns": ["table_size_b", "total_relation_size_b", "toast_size_b", "seconds_since_last_vacuum", "seconds_since_last_analyze", "n_live_tup", "n_dead_tup"]}',
true
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs, m_master_only)
values (
'table_stats',
9.1,
$sql$
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  quote_ident(schemaname) as tag_schema,
  quote_ident(ut.relname) as tag_table_name,
  quote_ident(schemaname)||'.'||quote_ident(ut.relname) as tag_table_full_name,
  pg_table_size(relid) as table_size_b,
  abs(greatest(ceil(log((pg_table_size(relid)+1) / 10^6)), 0))::text as tag_table_size_cardinality_mb, -- i.e. 0=<1MB, 1=<10MB, 2=<100MB,..
  pg_total_relation_size(relid) as total_relation_size_b,
  case when reltoastrelid != 0 then pg_total_relation_size(reltoastrelid) else 0::int8 end as toast_size_b,
  (extract(epoch from now() - greatest(last_vacuum, last_autovacuum)))::int8 as seconds_since_last_vacuum,
  (extract(epoch from now() - greatest(last_analyze, last_autoanalyze)))::int8 as seconds_since_last_analyze,
  case when 'autovacuum_enabled=off' = ANY(c.reloptions) then 1 else 0 end as no_autovacuum,
  seq_scan,
  seq_tup_read,
  coalesce(idx_scan, 0) as idx_scan,
  coalesce(idx_tup_fetch, 0) as idx_tup_fetch,
  n_tup_ins,
  n_tup_upd,
  n_tup_del,
  n_tup_hot_upd,
  n_live_tup,
  n_dead_tup,
  vacuum_count,
  autovacuum_count,
  analyze_count,
  autoanalyze_count,
  age(relfrozenxid) as tx_freeze_age
from
  pg_stat_user_tables ut
  join
  pg_class c on c.oid = ut.relid
where
  -- leaving out fully locked tables as pg_relation_size also wants a lock and would wait
  not exists (select 1 from pg_locks where relation = relid and mode = 'AccessExclusiveLock')
  and c.relpersistence != 't' -- and temp tables
order by table_size_b desc nulls last limit 300;
$sql$,
'{"prometheus_gauge_columns": ["table_size_b", "total_relation_size_b", "toast_size_b", "seconds_since_last_vacuum", "seconds_since_last_analyze", "n_live_tup", "n_dead_tup"]}',
true
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs, m_standby_only)
values (
'table_stats',
9.1,
$sql$
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  quote_ident(schemaname) as tag_schema,
  quote_ident(ut.relname) as tag_table_name,
  quote_ident(schemaname)||'.'||quote_ident(ut.relname) as tag_table_full_name,
  pg_table_size(relid) as table_size_b,
  abs(greatest(ceil(log((pg_table_size(relid)+1) / 10^6)), 0))::text as tag_table_size_cardinality_mb, -- i.e. 0=<1MB, 1=<10MB, 2=<100MB,..
  pg_total_relation_size(relid) as total_relation_size_b,
  case when reltoastrelid != 0 then pg_total_relation_size(reltoastrelid) else 0::int8 end as toast_size_b,
  (extract(epoch from now() - greatest(last_vacuum, last_autovacuum)))::int8 as seconds_since_last_vacuum,
  (extract(epoch from now() - greatest(last_analyze, last_autoanalyze)))::int8 as seconds_since_last_analyze,
  case when 'autovacuum_enabled=off' = ANY(c.reloptions) then 1 else 0 end as no_autovacuum,
  seq_scan,
  seq_tup_read,
  coalesce(idx_scan, 0) as idx_scan,
  coalesce(idx_tup_fetch, 0) as idx_tup_fetch,
  n_tup_ins,
  n_tup_upd,
  n_tup_del,
  n_tup_hot_upd,
  n_live_tup,
  n_dead_tup,
  vacuum_count,
  autovacuum_count,
  analyze_count,
  autoanalyze_count,
  age(relfrozenxid) as tx_freeze_age
from
  pg_stat_user_tables ut
  join
  pg_class c on c.oid = ut.relid
where
  -- leaving out fully locked tables as pg_relation_size also wants a lock and would wait
  not exists (select 1 from pg_locks where relation = relid and mode = 'AccessExclusiveLock')
  and c.relpersistence != 't' -- and temp tables
order by table_size_b desc nulls last limit 300;
$sql$,
'{"prometheus_gauge_columns": ["table_size_b", "total_relation_size_b", "toast_size_b", "seconds_since_last_vacuum", "seconds_since_last_analyze", "n_live_tup", "n_dead_tup"]}',
true
);


insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs)
values (
'table_stats',
9.2,
$sql$
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  quote_ident(schemaname) as tag_schema,
  quote_ident(ut.relname) as tag_table_name,
  quote_ident(schemaname)||'.'||quote_ident(ut.relname) as tag_table_full_name,
  pg_table_size(relid) as table_size_b,
  abs(greatest(ceil(log((pg_table_size(relid)+1) / 10^6)), 0))::text as tag_table_size_cardinality_mb, -- i.e. 0=<1MB, 1=<10MB, 2=<100MB,..
  pg_total_relation_size(relid) as total_relation_size_b,
  case when reltoastrelid != 0 then pg_total_relation_size(reltoastrelid) else 0::int8 end as toast_size_b,
  (extract(epoch from now() - greatest(last_vacuum, last_autovacuum)))::int8 as seconds_since_last_vacuum,
  (extract(epoch from now() - greatest(last_analyze, last_autoanalyze)))::int8 as seconds_since_last_analyze,
  case when 'autovacuum_enabled=off' = ANY(c.reloptions) then 1 else 0 end as no_autovacuum,
  seq_scan,
  seq_tup_read,
  coalesce(idx_scan, 0) as idx_scan,
  coalesce(idx_tup_fetch, 0) as idx_tup_fetch,
  n_tup_ins,
  n_tup_upd,
  n_tup_del,
  n_tup_hot_upd,
  n_live_tup,
  n_dead_tup,
  vacuum_count,
  autovacuum_count,
  analyze_count,
  autoanalyze_count,
  age(relfrozenxid) as tx_freeze_age
from
  pg_stat_user_tables ut
  join
  pg_class c on c.oid = ut.relid
where
  -- leaving out fully locked tables as pg_relation_size also wants a lock and would wait
  not exists (select 1 from pg_locks where relation = relid and mode = 'AccessExclusiveLock')
  and c.relpersistence != 't' -- and temp tables
order by table_size_b desc nulls last limit 300;
$sql$,
'{"prometheus_gauge_columns": ["table_size_b", "total_relation_size_b", "toast_size_b", "seconds_since_last_vacuum", "seconds_since_last_analyze", "n_live_tup", "n_dead_tup"]}'
);


insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs)
values (
'table_stats',
10,
$sql$
with recursive /* pgwatch2_generated */
    q_root_part as (
        select c.oid,
               c.relkind,
               n.nspname root_schema,
               c.relname root_relname
        from pg_class c
                 join pg_namespace n on n.oid = c.relnamespace
        where relkind in ('p', 'r')
          and relpersistence != 't'
          and not n.nspname like any (array[E'pg\\_%', 'information_schema', E'\\_timescaledb%'])
          and not exists(select * from pg_inherits where inhrelid = c.oid)
          and exists(select * from pg_inherits where inhparent = c.oid)
    ),
    q_parts (relid, relkind, level, root) as (
        select oid, relkind, 1, oid
        from q_root_part
        union all
        select inhrelid, c.relkind, level + 1, q.root
        from pg_inherits i
                 join q_parts q on inhparent = q.relid
                 join pg_class c on c.oid = i.inhrelid
    ),
    q_tstats as (
        select (extract(epoch from now()) * 1e9)::int8                                                  as epoch_ns,
               relid, -- not sent to final output
               quote_ident(schemaname)                                                                  as tag_schema,
               quote_ident(ut.relname)                                                                  as tag_table_name,
               quote_ident(schemaname) || '.' || quote_ident(ut.relname)                                as tag_table_full_name,
               pg_table_size(relid)                                                                     as table_size_b,
               abs(greatest(ceil(log((pg_table_size(relid) + 1) / 10 ^ 6)), 0))::text                   as tag_table_size_cardinality_mb, -- i.e. 0=<1MB, 1=<10MB, 2=<100MB,..
               pg_total_relation_size(relid)                                                            as total_relation_size_b,
               case when c.reltoastrelid != 0 then pg_total_relation_size(c.reltoastrelid) else 0::int8 end as toast_size_b,
               (extract(epoch from now() - greatest(last_vacuum, last_autovacuum)))::int8               as seconds_since_last_vacuum,
               (extract(epoch from now() - greatest(last_analyze, last_autoanalyze)))::int8             as seconds_since_last_analyze,
               case when 'autovacuum_enabled=off' = ANY (c.reloptions) then 1 else 0 end                as no_autovacuum,
               seq_scan,
               seq_tup_read,
               coalesce(idx_scan, 0) as idx_scan,
               coalesce(idx_tup_fetch, 0) as idx_tup_fetch,
               n_tup_ins,
               n_tup_upd,
               n_tup_del,
               n_tup_hot_upd,
               n_live_tup,
               n_dead_tup,
               vacuum_count,
               autovacuum_count,
               analyze_count,
               autoanalyze_count,
               age(c.relfrozenxid) as tx_freeze_age
        from pg_stat_user_tables ut
            join pg_class c on c.oid = ut.relid
            left join pg_class t on t.oid = c.reltoastrelid
            left join pg_index ti on ti.indrelid = t.oid
            left join pg_class tir on tir.oid = ti.indexrelid
        where
          -- leaving out fully locked tables as pg_relation_size also wants a lock and would wait
          not exists (select 1 from pg_locks where relation = relid and mode = 'AccessExclusiveLock')
          and c.relpersistence != 't' -- and temp tables
        order by case when c.relkind = 'p' then 1e9::int else coalesce(c.relpages, 0) + coalesce(t.relpages, 0) + coalesce(tir.relpages, 0) end desc
        limit 1500 /* NB! When changing the bottom final LIMIT also adjust this limit. Should be at least 5x bigger as approx sizes depend a lot on vacuum frequency.
                    The general idea is to reduce filesystem "stat"-ing on tables that won't make it to final output anyways based on approximate size */
    )

select /* pgwatch2_generated */
    epoch_ns,
    tag_schema,
    tag_table_name,
    tag_table_full_name,
    0 as is_part_root,
    table_size_b,
    tag_table_size_cardinality_mb, -- i.e. 0=<1MB, 1=<10MB, 2=<100MB,..
    total_relation_size_b,
    toast_size_b,
    seconds_since_last_vacuum,
    seconds_since_last_analyze,
    no_autovacuum,
    seq_scan,
    seq_tup_read,
    idx_scan,
    idx_tup_fetch,
    n_tup_ins,
    n_tup_upd,
    n_tup_del,
    n_tup_hot_upd,
    n_live_tup,
    n_dead_tup,
    vacuum_count,
    autovacuum_count,
    analyze_count,
    autoanalyze_count,
    tx_freeze_age
from q_tstats
where not tag_schema like E'\\_timescaledb%'
and not exists (select * from q_root_part where oid = q_tstats.relid)

union all

select * from (
    select
        epoch_ns,
        quote_ident(qr.root_schema) as tag_schema,
        quote_ident(qr.root_relname) as tag_table_name,
        quote_ident(qr.root_schema) || '.' || quote_ident(qr.root_relname) as tag_table_full_name,
        1 as is_part_root,
        sum(table_size_b)::int8 table_size_b,
        abs(greatest(ceil(log((sum(table_size_b) + 1) / 10 ^ 6)),
             0))::text as tag_table_size_cardinality_mb, -- i.e. 0=<1MB, 1=<10MB, 2=<100MB,..
        sum(total_relation_size_b)::int8 total_relation_size_b,
        sum(toast_size_b)::int8 toast_size_b,
        min(seconds_since_last_vacuum)::int8 seconds_since_last_vacuum,
        min(seconds_since_last_analyze)::int8 seconds_since_last_analyze,
        sum(no_autovacuum)::int8 no_autovacuum,
        sum(seq_scan)::int8 seq_scan,
        sum(seq_tup_read)::int8 seq_tup_read,
        sum(idx_scan)::int8 idx_scan,
        sum(idx_tup_fetch)::int8 idx_tup_fetch,
        sum(n_tup_ins)::int8 n_tup_ins,
        sum(n_tup_upd)::int8 n_tup_upd,
        sum(n_tup_del)::int8 n_tup_del,
        sum(n_tup_hot_upd)::int8 n_tup_hot_upd,
        sum(n_live_tup)::int8 n_live_tup,
        sum(n_dead_tup)::int8 n_dead_tup,
        sum(vacuum_count)::int8 vacuum_count,
        sum(autovacuum_count)::int8 autovacuum_count,
        sum(analyze_count)::int8 analyze_count,
        sum(autoanalyze_count)::int8 autoanalyze_count,
        max(tx_freeze_age)::int8 tx_freeze_age
      from
           q_tstats ts
           join q_parts qp on qp.relid = ts.relid
           join q_root_part qr on qr.oid = qp.root
      group by
           1, 2, 3, 4
) x
order by table_size_b desc nulls last limit 300;
$sql$,
'{"prometheus_gauge_columns": ["table_size_b", "total_relation_size_b", "toast_size_b", "seconds_since_last_vacuum", "seconds_since_last_analyze", "n_live_tup", "n_dead_tup"]}'
);


insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs)
values (
'table_stats',
16,
$sql$
with recursive /* pgwatch2_generated */
    q_root_part as (
        select c.oid,
               c.relkind,
               n.nspname root_schema,
               c.relname root_relname
        from pg_class c
                 join pg_namespace n on n.oid = c.relnamespace
        where relkind in ('p', 'r')
          and relpersistence != 't'
          and not n.nspname like any (array[E'pg\\_%', 'information_schema', E'\\_timescaledb%'])
          and not exists(select * from pg_inherits where inhrelid = c.oid)
          and exists(select * from pg_inherits where inhparent = c.oid)
    ),
    q_parts (relid, relkind, level, root) as (
        select oid, relkind, 1, oid
        from q_root_part
        union all
        select inhrelid, c.relkind, level + 1, q.root
        from pg_inherits i
                 join q_parts q on inhparent = q.relid
                 join pg_class c on c.oid = i.inhrelid
    ),
    q_tstats as (
        select (extract(epoch from now()) * 1e9)::int8                                                  as epoch_ns,
               relid, -- not sent to final output
               quote_ident(schemaname)                                                                  as tag_schema,
               quote_ident(ut.relname)                                                                  as tag_table_name,
               quote_ident(schemaname) || '.' || quote_ident(ut.relname)                                as tag_table_full_name,
               pg_table_size(relid)                                                                     as table_size_b,
               abs(greatest(ceil(log((pg_table_size(relid) + 1) / 10 ^ 6)), 0))::text                   as tag_table_size_cardinality_mb, -- i.e. 0=<1MB, 1=<10MB, 2=<100MB,..
               pg_total_relation_size(relid)                                                            as total_relation_size_b,
               case when c.reltoastrelid != 0 then pg_total_relation_size(c.reltoastrelid) else 0::int8 end as toast_size_b,
               (extract(epoch from now() - greatest(last_vacuum, last_autovacuum)))::int8               as seconds_since_last_vacuum,
               (extract(epoch from now() - greatest(last_analyze, last_autoanalyze)))::int8             as seconds_since_last_analyze,
               case when 'autovacuum_enabled=off' = ANY (c.reloptions) then 1 else 0 end                as no_autovacuum,
               seq_scan,
               seq_tup_read,
               coalesce(idx_scan, 0) as idx_scan,
               coalesce(idx_tup_fetch, 0) as idx_tup_fetch,
               n_tup_ins,
               n_tup_upd,
               n_tup_del,
               n_tup_hot_upd,
               n_live_tup,
               n_dead_tup,
               vacuum_count,
               autovacuum_count,
               analyze_count,
               autoanalyze_count,
               age(c.relfrozenxid) as tx_freeze_age,
               extract(epoch from now() - last_seq_scan)::int8 as last_seq_scan_s
        from pg_stat_user_tables ut
            join pg_class c on c.oid = ut.relid
            left join pg_class t on t.oid = c.reltoastrelid
            left join pg_index ti on ti.indrelid = t.oid
            left join pg_class tir on tir.oid = ti.indexrelid
        where
          -- leaving out fully locked tables as pg_relation_size also wants a lock and would wait
          not exists (select 1 from pg_locks where relation = relid and mode = 'AccessExclusiveLock')
          and c.relpersistence != 't' -- and temp tables
        order by case when c.relkind = 'p' then 1e9::int else coalesce(c.relpages, 0) + coalesce(t.relpages, 0) + coalesce(tir.relpages, 0) end desc
        limit 1500 /* NB! When changing the bottom final LIMIT also adjust this limit. Should be at least 5x bigger as approx sizes depend a lot on vacuum frequency.
                    The general idea is to reduce filesystem "stat"-ing on tables that won't make it to final output anyways based on approximate size */
    )

select /* pgwatch2_generated */
    epoch_ns,
    tag_schema,
    tag_table_name,
    tag_table_full_name,
    0 as is_part_root,
    table_size_b,
    tag_table_size_cardinality_mb, -- i.e. 0=<1MB, 1=<10MB, 2=<100MB,..
    total_relation_size_b,
    toast_size_b,
    seconds_since_last_vacuum,
    seconds_since_last_analyze,
    no_autovacuum,
    seq_scan,
    seq_tup_read,
    idx_scan,
    idx_tup_fetch,
    n_tup_ins,
    n_tup_upd,
    n_tup_del,
    n_tup_hot_upd,
    n_live_tup,
    n_dead_tup,
    vacuum_count,
    autovacuum_count,
    analyze_count,
    autoanalyze_count,
    tx_freeze_age,
    last_seq_scan_s
from q_tstats
where not tag_schema like E'\\_timescaledb%'
and not exists (select * from q_root_part where oid = q_tstats.relid)

union all

select * from (
    select
        epoch_ns,
        quote_ident(qr.root_schema) as tag_schema,
        quote_ident(qr.root_relname) as tag_table_name,
        quote_ident(qr.root_schema) || '.' || quote_ident(qr.root_relname) as tag_table_full_name,
        1 as is_part_root,
        sum(table_size_b)::int8 table_size_b,
        abs(greatest(ceil(log((sum(table_size_b) + 1) / 10 ^ 6)),
             0))::text as tag_table_size_cardinality_mb, -- i.e. 0=<1MB, 1=<10MB, 2=<100MB,..
        sum(total_relation_size_b)::int8 total_relation_size_b,
        sum(toast_size_b)::int8 toast_size_b,
        min(seconds_since_last_vacuum)::int8 seconds_since_last_vacuum,
        min(seconds_since_last_analyze)::int8 seconds_since_last_analyze,
        sum(no_autovacuum)::int8 no_autovacuum,
        sum(seq_scan)::int8 seq_scan,
        sum(seq_tup_read)::int8 seq_tup_read,
        sum(idx_scan)::int8 idx_scan,
        sum(idx_tup_fetch)::int8 idx_tup_fetch,
        sum(n_tup_ins)::int8 n_tup_ins,
        sum(n_tup_upd)::int8 n_tup_upd,
        sum(n_tup_del)::int8 n_tup_del,
        sum(n_tup_hot_upd)::int8 n_tup_hot_upd,
        sum(n_live_tup)::int8 n_live_tup,
        sum(n_dead_tup)::int8 n_dead_tup,
        sum(vacuum_count)::int8 vacuum_count,
        sum(autovacuum_count)::int8 autovacuum_count,
        sum(analyze_count)::int8 analyze_count,
        sum(autoanalyze_count)::int8 autoanalyze_count,
        max(tx_freeze_age)::int8 tx_freeze_age,
        min(last_seq_scan_s)::int8 last_seq_scan_s
      from
           q_tstats ts
           join q_parts qp on qp.relid = ts.relid
           join q_root_part qr on qr.oid = qp.root
      group by
           1, 2, 3, 4
) x
order by table_size_b desc nulls last limit 300;
$sql$,
'{"prometheus_gauge_columns": ["table_size_b", "total_relation_size_b", "toast_size_b", "seconds_since_last_vacuum", "seconds_since_last_analyze", "n_live_tup", "n_dead_tup"]}'
);

/* table_stats_approx */

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs, m_master_only)
values (
'table_stats_approx',
9.0,
$sql$
with q_tbls_by_total_associated_relpages_approx as (
  select * from (
    select
      c.oid,
      c.relname,
      c.relpages,
      coalesce((select sum(relpages) from pg_class ci join pg_index i on i.indexrelid = ci.oid where i.indrelid = c.oid), 0) as index_relpages,
      coalesce((select coalesce(ct.relpages, 0) + coalesce(cti.relpages, 0) from pg_class ct left join pg_index ti on ti.indrelid = ct.oid left join pg_class cti on cti.oid = ti.indexrelid where ct.oid = c.reltoastrelid), 0) as toast_relpages,
      case when 'autovacuum_enabled=off' = ANY(c.reloptions) then 1 else 0 end as no_autovacuum,
      age(c.relfrozenxid) as tx_freeze_age
    from
      pg_class c
      join pg_namespace n on n.oid = c.relnamespace
    where
      not n.nspname like any (array[E'pg\\_%', 'information_schema'])
      and c.relkind = 'r'
      and not relistemp -- and temp tables
  ) x
  order by relpages + index_relpages + toast_relpages desc limit 300
), q_block_size as (
  select current_setting('block_size')::int8 as bs
)
select /* pgwatch2_generated */
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  quote_ident(schemaname)||'.'||quote_ident(ut.relname) as tag_table_full_name,
  bs * relpages as table_size_b,
  abs(greatest(ceil(log((bs*relpages+1) / 10^6)), 0))::text as tag_table_size_cardinality_mb, -- i.e. 0=<1MB, 1=<10MB, 2=<100MB,..
  bs * (relpages + index_relpages + toast_relpages) as total_relation_size_b,
  bs * toast_relpages as toast_size_b,
  (extract(epoch from now() - greatest(last_vacuum, last_autovacuum)))::int8 as seconds_since_last_vacuum,
  (extract(epoch from now() - greatest(last_analyze, last_autoanalyze)))::int8 as seconds_since_last_analyze,
  no_autovacuum,
  seq_scan,
  seq_tup_read,
  coalesce(idx_scan, 0) as idx_scan,
  coalesce(idx_tup_fetch, 0) as idx_tup_fetch,
  n_tup_ins,
  n_tup_upd,
  n_tup_del,
  n_tup_hot_upd,
  n_live_tup,
  n_dead_tup,
  tx_freeze_age
from
  pg_stat_user_tables ut
  join q_tbls_by_total_associated_relpages_approx t on t.oid = ut.relid
  join q_block_size on true
where
  -- leaving out fully locked tables as pg_relation_size also wants a lock and would wait
  not exists (select 1 from pg_locks where relation = relid and mode = 'AccessExclusiveLock');
$sql$,
'{"prometheus_gauge_columns": ["table_size_b", "total_relation_size_b", "toast_size_b", "seconds_since_last_vacuum", "seconds_since_last_analyze", "n_live_tup", "n_dead_tup"]}',
true
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs, m_standby_only)
values (
'table_stats_approx',
9.0,
$sql$
with q_tbls_by_total_associated_relpages_approx as (
  select * from (
    select
      c.oid,
      c.relname,
      c.relpages,
      coalesce((select sum(relpages) from pg_class ci join pg_index i on i.indexrelid = ci.oid where i.indrelid = c.oid), 0) as index_relpages,
      coalesce((select coalesce(ct.relpages, 0) + coalesce(cti.relpages, 0) from pg_class ct left join pg_index ti on ti.indrelid = ct.oid left join pg_class cti on cti.oid = ti.indexrelid where ct.oid = c.reltoastrelid), 0) as toast_relpages,
      case when 'autovacuum_enabled=off' = ANY(c.reloptions) then 1 else 0 end as no_autovacuum
    from
      pg_class c
      join pg_namespace n on n.oid = c.relnamespace
    where
      not n.nspname like any (array[E'pg\\_%', 'information_schema'])
      and c.relkind = 'r'
      and not relistemp -- and temp tables
  ) x
  order by relpages + index_relpages + toast_relpages desc limit 300
), q_block_size as (
  select current_setting('block_size')::int8 as bs
)
select /* pgwatch2_generated */
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  quote_ident(schemaname)||'.'||quote_ident(ut.relname) as tag_table_full_name,
  bs * relpages as table_size_b,
  abs(greatest(ceil(log((bs*relpages+1) / 10^6)), 0))::text as tag_table_size_cardinality_mb, -- i.e. 0=<1MB, 1=<10MB, 2=<100MB,..
  bs * (relpages + index_relpages + toast_relpages) as total_relation_size_b,
  bs * toast_relpages as toast_size_b,
  (extract(epoch from now() - greatest(last_vacuum, last_autovacuum)))::int8 as seconds_since_last_vacuum,
  (extract(epoch from now() - greatest(last_analyze, last_autoanalyze)))::int8 as seconds_since_last_analyze,
  no_autovacuum,
  seq_scan,
  seq_tup_read,
  coalesce(idx_scan, 0) as idx_scan,
  coalesce(idx_tup_fetch, 0) as idx_tup_fetch,
  n_tup_ins,
  n_tup_upd,
  n_tup_del,
  n_tup_hot_upd,
  n_live_tup,
  n_dead_tup
from
  pg_stat_user_tables ut
  join q_tbls_by_total_associated_relpages_approx t on t.oid = ut.relid
  join q_block_size on true
where
  -- leaving out fully locked tables as pg_relation_size also wants a lock and would wait
  not exists (select 1 from pg_locks where relation = relid and mode = 'AccessExclusiveLock');
$sql$,
'{"prometheus_gauge_columns": ["table_size_b", "total_relation_size_b", "toast_size_b", "seconds_since_last_vacuum", "seconds_since_last_analyze", "n_live_tup", "n_dead_tup"]}',
true
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs, m_master_only)
values (
'table_stats_approx',
9.1,
$sql$
with q_tbls_by_total_associated_relpages_approx as (
  select * from (
    select
      c.oid,
      c.relname,
      c.relpages,
      coalesce((select sum(relpages) from pg_class ci join pg_index i on i.indexrelid = ci.oid where i.indrelid = c.oid), 0) as index_relpages,
      coalesce((select coalesce(ct.relpages, 0) + coalesce(cti.relpages, 0) from pg_class ct left join pg_index ti on ti.indrelid = ct.oid left join pg_class cti on cti.oid = ti.indexrelid where ct.oid = c.reltoastrelid), 0) as toast_relpages,
      case when 'autovacuum_enabled=off' = ANY(c.reloptions) then 1 else 0 end as no_autovacuum,
      age(c.relfrozenxid) as tx_freeze_age,
      c.relpersistence
    from
      pg_class c
      join pg_namespace n on n.oid = c.relnamespace
    where
      not n.nspname like any (array[E'pg\\_%', 'information_schema'])
      and c.relkind = 'r'
      and c.relpersistence != 't'
  ) x
  order by relpages + index_relpages + toast_relpages desc limit 300
), q_block_size as (
  select current_setting('block_size')::int8 as bs
)
select /* pgwatch2_generated */
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  quote_ident(schemaname)||'.'||quote_ident(ut.relname) as tag_table_full_name,
  bs * relpages as table_size_b,
  abs(greatest(ceil(log((bs*relpages+1) / 10^6)), 0))::text as tag_table_size_cardinality_mb, -- i.e. 0=<1MB, 1=<10MB, 2=<100MB,..
  bs * (relpages + index_relpages + toast_relpages) as total_relation_size_b,
  bs * toast_relpages as toast_size_b,
  (extract(epoch from now() - greatest(last_vacuum, last_autovacuum)))::int8 as seconds_since_last_vacuum,
  (extract(epoch from now() - greatest(last_analyze, last_autoanalyze)))::int8 as seconds_since_last_analyze,
  no_autovacuum,
  seq_scan,
  seq_tup_read,
  coalesce(idx_scan, 0) as idx_scan,
  coalesce(idx_tup_fetch, 0) as idx_tup_fetch,
  n_tup_ins,
  n_tup_upd,
  n_tup_del,
  n_tup_hot_upd,
  n_live_tup,
  n_dead_tup,
  vacuum_count,
  autovacuum_count,
  analyze_count,
  autoanalyze_count,
  tx_freeze_age,
  relpersistence
from
  pg_stat_user_tables ut
  join q_tbls_by_total_associated_relpages_approx t on t.oid = ut.relid
  join q_block_size on true
where
  -- leaving out fully locked tables as pg_relation_size also wants a lock and would wait
  not exists (select 1 from pg_locks where relation = relid and mode = 'AccessExclusiveLock');
$sql$,
'{"prometheus_gauge_columns": ["table_size_b", "total_relation_size_b", "toast_size_b", "seconds_since_last_vacuum", "seconds_since_last_analyze", "n_live_tup", "n_dead_tup"]}',
true
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs, m_standby_only)
values (
'table_stats_approx',
9.1,
$sql$
with q_tbls_by_total_associated_relpages_approx as (
  select * from (
    select
      c.oid,
      c.relname,
      c.relpages,
      coalesce((select sum(relpages) from pg_class ci join pg_index i on i.indexrelid = ci.oid where i.indrelid = c.oid), 0) as index_relpages,
      coalesce((select coalesce(ct.relpages, 0) + coalesce(cti.relpages, 0) from pg_class ct left join pg_index ti on ti.indrelid = ct.oid left join pg_class cti on cti.oid = ti.indexrelid where ct.oid = c.reltoastrelid), 0) as toast_relpages,
      case when 'autovacuum_enabled=off' = ANY(c.reloptions) then 1 else 0 end as no_autovacuum,
      c.relpersistence
    from
      pg_class c
      join pg_namespace n on n.oid = c.relnamespace
    where
      not n.nspname like any (array[E'pg\\_%', 'information_schema'])
      and c.relkind = 'r'
      and c.relpersistence != 't'
  ) x
  order by relpages + index_relpages + toast_relpages desc limit 300
), q_block_size as (
  select current_setting('block_size')::int8 as bs
)
select /* pgwatch2_generated */
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  quote_ident(schemaname)||'.'||quote_ident(ut.relname) as tag_table_full_name,
  bs * relpages as table_size_b,
  abs(greatest(ceil(log((bs*relpages+1) / 10^6)), 0))::text as tag_table_size_cardinality_mb, -- i.e. 0=<1MB, 1=<10MB, 2=<100MB,..
  bs * (relpages + index_relpages + toast_relpages) as total_relation_size_b,
  bs * toast_relpages as toast_size_b,
  (extract(epoch from now() - greatest(last_vacuum, last_autovacuum)))::int8 as seconds_since_last_vacuum,
  (extract(epoch from now() - greatest(last_analyze, last_autoanalyze)))::int8 as seconds_since_last_analyze,
  no_autovacuum,
  seq_scan,
  seq_tup_read,
  coalesce(idx_scan, 0) as idx_scan,
  coalesce(idx_tup_fetch, 0) as idx_tup_fetch,
  n_tup_ins,
  n_tup_upd,
  n_tup_del,
  n_tup_hot_upd,
  n_live_tup,
  n_dead_tup,
  vacuum_count,
  autovacuum_count,
  analyze_count,
  autoanalyze_count,
  relpersistence
from
  pg_stat_user_tables ut
  join q_tbls_by_total_associated_relpages_approx t on t.oid = ut.relid
  join q_block_size on true
where
  -- leaving out fully locked tables as pg_relation_size also wants a lock and would wait
  not exists (select 1 from pg_locks where relation = relid and mode = 'AccessExclusiveLock');
$sql$,
'{"prometheus_gauge_columns": ["table_size_b", "total_relation_size_b", "toast_size_b", "seconds_since_last_vacuum", "seconds_since_last_analyze", "n_live_tup", "n_dead_tup"]}',
true
);


insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs)
values (
'table_stats_approx',
9.2,
$sql$
with q_tbls_by_total_associated_relpages_approx as (
  select * from (
    select
      c.oid,
      c.relname,
      c.relpages,
      coalesce((select sum(relpages) from pg_class ci join pg_index i on i.indexrelid = ci.oid where i.indrelid = c.oid), 0) as index_relpages,
      coalesce((select coalesce(ct.relpages, 0) + coalesce(cti.relpages, 0) from pg_class ct left join pg_index ti on ti.indrelid = ct.oid left join pg_class cti on cti.oid = ti.indexrelid where ct.oid = c.reltoastrelid), 0) as toast_relpages,
      case when 'autovacuum_enabled=off' = ANY(c.reloptions) then 1 else 0 end as no_autovacuum,
      age(c.relfrozenxid) as tx_freeze_age,
      c.relpersistence
    from
      pg_class c
      join pg_namespace n on n.oid = c.relnamespace
    where
      not n.nspname like any (array[E'pg\\_%', 'information_schema'])
      and c.relkind = 'r'
      and c.relpersistence != 't'
  ) x
  order by relpages + index_relpages + toast_relpages desc limit 300
), q_block_size as (
  select current_setting('block_size')::int8 as bs
)
select /* pgwatch2_generated */
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  quote_ident(schemaname)||'.'||quote_ident(ut.relname) as tag_table_full_name,
  bs * relpages as table_size_b,
  abs(greatest(ceil(log((bs*relpages+1) / 10^6)), 0))::text as tag_table_size_cardinality_mb, -- i.e. 0=<1MB, 1=<10MB, 2=<100MB,..
  bs * (relpages + index_relpages + toast_relpages) as total_relation_size_b,
  bs * toast_relpages as toast_size_b,
  (extract(epoch from now() - greatest(last_vacuum, last_autovacuum)))::int8 as seconds_since_last_vacuum,
  (extract(epoch from now() - greatest(last_analyze, last_autoanalyze)))::int8 as seconds_since_last_analyze,
  no_autovacuum,
  seq_scan,
  seq_tup_read,
  coalesce(idx_scan, 0) as idx_scan,
  coalesce(idx_tup_fetch, 0) as idx_tup_fetch,
  n_tup_ins,
  n_tup_upd,
  n_tup_del,
  n_tup_hot_upd,
  n_live_tup,
  n_dead_tup,
  vacuum_count,
  autovacuum_count,
  analyze_count,
  autoanalyze_count,
  tx_freeze_age,
  relpersistence
from
  pg_stat_user_tables ut
  join q_tbls_by_total_associated_relpages_approx t on t.oid = ut.relid
  join q_block_size on true
where
  -- leaving out fully locked tables as pg_relation_size also wants a lock and would wait
  not exists (select 1 from pg_locks where relation = relid and mode = 'AccessExclusiveLock');
$sql$,
'{"prometheus_gauge_columns": ["table_size_b", "total_relation_size_b", "toast_size_b", "seconds_since_last_vacuum", "seconds_since_last_analyze", "n_live_tup", "n_dead_tup"]}'
);


insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs)
values (
'table_stats_approx',
10,
$sql$
with recursive
    q_root_part as (
        select c.oid,
               c.relkind,
               n.nspname root_schema,
               c.relname root_relname
        from pg_class c
                 join pg_namespace n on n.oid = c.relnamespace
        where relkind in ('p', 'r')
          and relpersistence != 't'
          and not n.nspname like any (array[E'pg\\_%', 'information_schema', E'\\_timescaledb%'])
          and not exists(select * from pg_inherits where inhrelid = c.oid)
          and exists(select * from pg_inherits where inhparent = c.oid)
    ),
    q_parts (relid, relkind, level, root) as (
        select oid, relkind, 1, oid
        from q_root_part
        union all
        select inhrelid, c.relkind, level + 1, q.root
        from pg_inherits i
                 join q_parts q on inhparent = q.relid
                 join pg_class c on c.oid = i.inhrelid
    ),
    q_tstats as (
      with q_tbls_by_total_associated_relpages_approx as (
        select * from (
          select
            c.oid,
            c.relname,
            c.relpages,
            coalesce((select sum(relpages) from pg_class ci join pg_index i on i.indexrelid = ci.oid where i.indrelid = c.oid), 0) as index_relpages,
            coalesce((select coalesce(ct.relpages, 0) + coalesce(cti.relpages, 0) from pg_class ct left join pg_index ti on ti.indrelid = ct.oid left join pg_class cti on cti.oid = ti.indexrelid where ct.oid = c.reltoastrelid), 0) as toast_relpages,
            case when 'autovacuum_enabled=off' = ANY(c.reloptions) then 1 else 0 end as no_autovacuum,
            age(c.relfrozenxid) as tx_freeze_age,
            c.relpersistence
          from
            pg_class c
            join pg_namespace n on n.oid = c.relnamespace
          where
            not n.nspname like any (array[E'pg\\_%', 'information_schema', E'\\_timescaledb%'])
            and c.relkind = 'r'
            and c.relpersistence != 't'
        ) x
        order by relpages + index_relpages + toast_relpages desc limit 300
      ), q_block_size as (
        select current_setting('block_size')::int8 as bs
      )
      select /* pgwatch2_generated */
        (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
        relid,
        quote_ident(schemaname)||'.'||quote_ident(ut.relname) as tag_table_full_name,
        bs * relpages as table_size_b,
        abs(greatest(ceil(log((bs*relpages+1) / 10^6)), 0))::text as tag_table_size_cardinality_mb, -- i.e. 0=<1MB, 1=<10MB, 2=<100MB,..
        bs * (relpages + index_relpages + toast_relpages) as total_relation_size_b,
        bs * toast_relpages as toast_size_b,
        (extract(epoch from now() - greatest(last_vacuum, last_autovacuum)))::int8 as seconds_since_last_vacuum,
        (extract(epoch from now() - greatest(last_analyze, last_autoanalyze)))::int8 as seconds_since_last_analyze,
        no_autovacuum,
        seq_scan,
        seq_tup_read,
        coalesce(idx_scan, 0) as idx_scan,
        coalesce(idx_tup_fetch, 0) as idx_tup_fetch,
        n_tup_ins,
        n_tup_upd,
        n_tup_del,
        n_tup_hot_upd,
        n_live_tup,
        n_dead_tup,
        vacuum_count,
        autovacuum_count,
        analyze_count,
        autoanalyze_count,
        tx_freeze_age,
        relpersistence
      from
        pg_stat_user_tables ut
        join q_tbls_by_total_associated_relpages_approx t on t.oid = ut.relid
        join q_block_size on true
      where
        -- leaving out fully locked tables as pg_relation_size also wants a lock and would wait
        not exists (select 1 from pg_locks where relation = relid and mode = 'AccessExclusiveLock')
      order by relpages desc

    )

select /* pgwatch2_generated */
    epoch_ns,
    tag_table_full_name,
    0 as is_part_root,
    table_size_b,
    tag_table_size_cardinality_mb, -- i.e. 0=<1MB, 1=<10MB, 2=<100MB,..
    total_relation_size_b,
    toast_size_b,
    seconds_since_last_vacuum,
    seconds_since_last_analyze,
    no_autovacuum,
    seq_scan,
    seq_tup_read,
    idx_scan,
    idx_tup_fetch,
    n_tup_ins,
    n_tup_upd,
    n_tup_del,
    n_tup_hot_upd,
    n_live_tup,
    n_dead_tup,
    vacuum_count,
    autovacuum_count,
    analyze_count,
    autoanalyze_count,
    tx_freeze_age
from q_tstats
where not exists (select * from q_root_part where oid = q_tstats.relid)

union all

select * from (
    select
        epoch_ns,
        quote_ident(qr.root_schema) || '.' || quote_ident(qr.root_relname) as tag_table_full_name,
        1 as is_part_root,
        sum(table_size_b)::int8 table_size_b,
        abs(greatest(ceil(log((sum(table_size_b) + 1) / 10 ^ 6)),
             0))::text as tag_table_size_cardinality_mb, -- i.e. 0=<1MB, 1=<10MB, 2=<100MB,..
        sum(total_relation_size_b)::int8 total_relation_size_b,
        sum(toast_size_b)::int8 toast_size_b,
        min(seconds_since_last_vacuum)::int8 seconds_since_last_vacuum,
        min(seconds_since_last_analyze)::int8 seconds_since_last_analyze,
        sum(no_autovacuum)::int8 no_autovacuum,
        sum(seq_scan)::int8 seq_scan,
        sum(seq_tup_read)::int8 seq_tup_read,
        sum(idx_scan)::int8 idx_scan,
        sum(idx_tup_fetch)::int8 idx_tup_fetch,
        sum(n_tup_ins)::int8 n_tup_ins,
        sum(n_tup_upd)::int8 n_tup_upd,
        sum(n_tup_del)::int8 n_tup_del,
        sum(n_tup_hot_upd)::int8 n_tup_hot_upd,
        sum(n_live_tup)::int8 n_live_tup,
        sum(n_dead_tup)::int8 n_dead_tup,
        sum(vacuum_count)::int8 vacuum_count,
        sum(autovacuum_count)::int8 autovacuum_count,
        sum(analyze_count)::int8 analyze_count,
        sum(autoanalyze_count)::int8 autoanalyze_count,
        max(tx_freeze_age)::int8 tx_freeze_age
      from
           q_tstats ts
           join q_parts qp on qp.relid = ts.relid
           join q_root_part qr on qr.oid = qp.root
      group by
           1, 2
) x;
$sql$,
'{"prometheus_gauge_columns": ["table_size_b", "total_relation_size_b", "toast_size_b", "seconds_since_last_vacuum", "seconds_since_last_analyze", "n_live_tup", "n_dead_tup"]}'
);


/* wal */

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs)
values (
'wal',
9.2,
$sql$
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  case
    when pg_is_in_recovery() = false then
      pg_xlog_location_diff(pg_current_xlog_location(), '0/0')::int8
    else
      pg_xlog_location_diff(pg_last_xlog_replay_location(), '0/0')::int8
    end as xlog_location_b,
  case when pg_is_in_recovery() then 1 else 0 end as in_recovery_int,
  extract(epoch from (now() - pg_postmaster_start_time()))::int8 as postmaster_uptime_s;
$sql$,
'{"prometheus_gauge_columns": ["in_recovery_int", "postmaster_uptime_s"]}'
);


/* wal */

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_sql_su, m_column_attrs)
values (
'wal',
10,
$sql$
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  case
    when pg_is_in_recovery() = false then
      pg_wal_lsn_diff(pg_current_wal_lsn(), '0/0')::int8
    else
      pg_wal_lsn_diff(pg_last_wal_replay_lsn(), '0/0')::int8
    end as xlog_location_b,
  case when pg_is_in_recovery() then 1 else 0 end as in_recovery_int,
  extract(epoch from (now() - pg_postmaster_start_time()))::int8 as postmaster_uptime_s,
  system_identifier::text as tag_sys_id,
  case
    when pg_is_in_recovery() = false then
      ('x'||substr(pg_walfile_name(pg_current_wal_lsn()), 1, 8))::bit(32)::int
    else
      (select min_recovery_end_timeline::int from pg_control_recovery())
    end as timeline
from pg_control_system();
$sql$,
$sql$
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  case
    when pg_is_in_recovery() = false then
      pg_wal_lsn_diff(pg_current_wal_lsn(), '0/0')::int8
    else
      pg_wal_lsn_diff(pg_last_wal_replay_lsn(), '0/0')::int8
    end as xlog_location_b,
  case when pg_is_in_recovery() then 1 else 0 end as in_recovery_int,
  extract(epoch from (now() - coalesce((pg_stat_file('postmaster.pid', true)).modification, pg_postmaster_start_time())))::int8 as postmaster_uptime_s,
  system_identifier::text as tag_sys_id,
  case
    when pg_is_in_recovery() = false then
      ('x'||substr(pg_walfile_name(pg_current_wal_lsn()), 1, 8))::bit(32)::int
    else
      (select min_recovery_end_timeline::int from pg_control_recovery())
    end as timeline
from pg_control_system();
$sql$,
'{"prometheus_gauge_columns": ["in_recovery_int", "postmaster_uptime_s"]}'
);

/* stat_statements */

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_sql_su)
values (
'stat_statements',
9.2,
$sql$
WITH q_data AS (
    SELECT
        (regexp_replace(md5(query::varchar(1000)), E'\\D', '', 'g'))::varchar(10)::text as tag_queryid,
        max(query::varchar(8000)) AS query,
        /*
         NB! if security conscious about exposing query texts replace the below expression with a dash ('-') OR
         use the stat_statements_no_query_text metric instead, created specifically for this use case.
         */
        array_to_string(array_agg(DISTINCT quote_ident(pg_get_userbyid(userid))), ',') AS users,
        sum(s.calls)::int8 AS calls,
        round(sum(s.total_time)::numeric, 3)::double precision AS total_time,
        sum(shared_blks_hit)::int8 AS shared_blks_hit,
        sum(shared_blks_read)::int8 AS shared_blks_read,
        sum(shared_blks_written)::int8 AS shared_blks_written,
        sum(shared_blks_dirtied)::int8 AS shared_blks_dirtied,
        sum(temp_blks_read)::int8 AS temp_blks_read,
        sum(temp_blks_written)::int8 AS temp_blks_written,
        round(sum(blk_read_time)::numeric, 3)::double precision AS blk_read_time,
        round(sum(blk_write_time)::numeric, 3)::double precision AS blk_write_time
    FROM
        get_stat_statements() s
    WHERE
        calls > 5
        AND total_time > 5
        AND dbid = (
            SELECT
                oid
            FROM
                pg_database
            WHERE
                datname = current_database())
            AND NOT upper(s.query::varchar(50))
            LIKE ANY (ARRAY['DEALLOCATE%',
                'SET %',
                'RESET %',
                'BEGIN%',
                'BEGIN;',
                'COMMIT%',
                'END%',
                'ROLLBACK%',
                'SHOW%'])
        GROUP BY
            tag_queryid
)
SELECT (EXTRACT(epoch FROM now()) * 1e9)::int8 AS epoch_ns,
       b.tag_queryid,
       b.users,
       b.calls,
       b.total_time,
       b.shared_blks_hit,
       b.shared_blks_read,
       b.shared_blks_written,
       b.shared_blks_dirtied,
       b.temp_blks_read,
       b.temp_blks_written,
       b.blk_read_time,
       b.blk_write_time,
       ltrim(regexp_replace(b.query, E'[ \\t\\n\\r]+', ' ', 'g')) tag_query
FROM (
    SELECT
        *
    FROM (
        SELECT
            *
        FROM
            q_data
        WHERE
            total_time > 0
        ORDER BY
            total_time DESC
        LIMIT 100) a
UNION
SELECT
    *
FROM (
    SELECT
        *
    FROM
        q_data
    ORDER BY
        calls DESC
    LIMIT 100) a
UNION
SELECT
    *
FROM (
    SELECT
        *
    FROM
        q_data
    WHERE
        shared_blks_read > 0
    ORDER BY
        shared_blks_read DESC
    LIMIT 100) a
UNION
SELECT
    *
FROM (
    SELECT
        *
    FROM
        q_data
    WHERE
        shared_blks_written > 0
    ORDER BY
        shared_blks_written DESC
    LIMIT 100) a
UNION
SELECT
    *
FROM (
    SELECT
        *
    FROM
        q_data
    WHERE
        temp_blks_read > 0
    ORDER BY
        temp_blks_read DESC
    LIMIT 100) a
UNION
SELECT
    *
FROM (
    SELECT
        *
    FROM
        q_data
    WHERE
        temp_blks_written > 0
    ORDER BY
        temp_blks_written DESC
    LIMIT 100) a) b;
$sql$,
$sql$
WITH q_data AS (
    SELECT
        (regexp_replace(md5(query::varchar(1000)), E'\\D', '', 'g'))::varchar(10)::text as tag_queryid,
        max(query::varchar(8000)) AS query,
        /*
         NB! if security conscious about exposing query texts replace the below expression with a dash ('-') OR
         use the stat_statements_no_query_text metric instead, created specifically for this use case.
         */
        array_to_string(array_agg(DISTINCT quote_ident(pg_get_userbyid(userid))), ',') AS users,
        sum(s.calls)::int8 AS calls,
        round(sum(s.total_time)::numeric, 3)::double precision AS total_time,
        sum(shared_blks_hit)::int8 AS shared_blks_hit,
        sum(shared_blks_read)::int8 AS shared_blks_read,
        sum(shared_blks_written)::int8 AS shared_blks_written,
        sum(shared_blks_dirtied)::int8 AS shared_blks_dirtied,
        sum(temp_blks_read)::int8 AS temp_blks_read,
        sum(temp_blks_written)::int8 AS temp_blks_written,
        round(sum(blk_read_time)::numeric, 3)::double precision AS blk_read_time,
        round(sum(blk_write_time)::numeric, 3)::double precision AS blk_write_time
    FROM
        pg_stat_statements s
    WHERE
        calls > 5
        AND total_time > 5
        AND dbid = (
            SELECT
                oid
            FROM
                pg_database
            WHERE
                datname = current_database())
            AND NOT upper(s.query::varchar(50))
            LIKE ANY (ARRAY['DEALLOCATE%',
                'SET %',
                'RESET %',
                'BEGIN%',
                'BEGIN;',
                'COMMIT%',
                'END%',
                'ROLLBACK%',
                'SHOW%'])
        GROUP BY
            tag_queryid
)
SELECT (EXTRACT(epoch FROM now()) * 1e9)::int8 AS epoch_ns,
       b.tag_queryid,
       b.users,
       b.calls,
       b.total_time,
       b.shared_blks_hit,
       b.shared_blks_read,
       b.shared_blks_written,
       b.shared_blks_dirtied,
       b.temp_blks_read,
       b.temp_blks_written,
       b.blk_read_time,
       b.blk_write_time,
       ltrim(regexp_replace(b.query, E'[ \\t\\n\\r]+', ' ', 'g')) tag_query
FROM (
    SELECT
        *
    FROM (
        SELECT
            *
        FROM
            q_data
        WHERE
            total_time > 0
        ORDER BY
            total_time DESC
        LIMIT 100) a
UNION
SELECT
    *
FROM (
    SELECT
        *
    FROM
        q_data
    ORDER BY
        calls DESC
    LIMIT 100) a
UNION
SELECT
    *
FROM (
    SELECT
        *
    FROM
        q_data
    WHERE
        shared_blks_read > 0
    ORDER BY
        shared_blks_read DESC
    LIMIT 100) a
UNION
SELECT
    *
FROM (
    SELECT
        *
    FROM
        q_data
    WHERE
        shared_blks_written > 0
    ORDER BY
        shared_blks_written DESC
    LIMIT 100) a
UNION
SELECT
    *
FROM (
    SELECT
        *
    FROM
        q_data
    WHERE
        temp_blks_read > 0
    ORDER BY
        temp_blks_read DESC
    LIMIT 100) a
UNION
SELECT
    *
FROM (
    SELECT
        *
    FROM
        q_data
    WHERE
        temp_blks_written > 0
    ORDER BY
        temp_blks_written DESC
    LIMIT 100) a) b;
$sql$
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_sql_su)
values (
'stat_statements',
9.4,
$sql$
WITH q_data AS (
    SELECT
        coalesce(queryid::text, 'insufficient-privileges-total') as tag_queryid,
        /*
         NB! if security conscious about exposing query texts replace the below expression with a dash ('-') OR
         use the stat_statements_no_query_text metric instead, created specifically for this use case.
         */
        array_to_string(array_agg(DISTINCT quote_ident(pg_get_userbyid(userid))), ',') AS users,
        sum(s.calls)::int8 AS calls,
        round(sum(s.total_time)::numeric, 3)::double precision AS total_time,
        sum(shared_blks_hit)::int8 AS shared_blks_hit,
        sum(shared_blks_read)::int8 AS shared_blks_read,
        sum(shared_blks_written)::int8 AS shared_blks_written,
        sum(shared_blks_dirtied)::int8 AS shared_blks_dirtied,
        sum(temp_blks_read)::int8 AS temp_blks_read,
        sum(temp_blks_written)::int8 AS temp_blks_written,
        round(sum(blk_read_time)::numeric, 3)::double precision AS blk_read_time,
        round(sum(blk_write_time)::numeric, 3)::double precision AS blk_write_time,
        max(query::varchar(8000)) AS query
    FROM
        get_stat_statements() s
    WHERE
        calls > 5
        AND total_time > 5
        AND dbid = (
            SELECT
                oid
            FROM
                pg_database
            WHERE
                datname = current_database())
            AND NOT upper(s.query::varchar(50))
            LIKE ANY (ARRAY['DEALLOCATE%',
                'SET %',
                'RESET %',
                'BEGIN%',
                'BEGIN;',
                'COMMIT%',
                'END%',
                'ROLLBACK%',
                'SHOW%'])
        GROUP BY
            queryid
)
SELECT (EXTRACT(epoch FROM now()) * 1e9)::int8 AS epoch_ns,
       b.tag_queryid,
       b.users,
       b.calls,
       b.total_time,
       b.shared_blks_hit,
       b.shared_blks_read,
       b.shared_blks_written,
       b.shared_blks_dirtied,
       b.temp_blks_read,
       b.temp_blks_written,
       b.blk_read_time,
       b.blk_write_time,
       ltrim(regexp_replace(b.query, E'[ \\t\\n\\r]+', ' ', 'g')) tag_query
FROM (
    SELECT
        *
    FROM (
        SELECT
            *
        FROM
            q_data
        WHERE
            total_time > 0
        ORDER BY
            total_time DESC
        LIMIT 100) a
UNION
SELECT
    *
FROM (
    SELECT
        *
    FROM
        q_data
    ORDER BY
        calls DESC
    LIMIT 100) a
UNION
SELECT
    *
FROM (
    SELECT
        *
    FROM
        q_data
    WHERE
        shared_blks_read > 0
    ORDER BY
        shared_blks_read DESC
    LIMIT 100) a
UNION
SELECT
    *
FROM (
    SELECT
        *
    FROM
        q_data
    WHERE
        shared_blks_written > 0
    ORDER BY
        shared_blks_written DESC
    LIMIT 100) a
UNION
SELECT
    *
FROM (
    SELECT
        *
    FROM
        q_data
    WHERE
        temp_blks_read > 0
    ORDER BY
        temp_blks_read DESC
    LIMIT 100) a
UNION
SELECT
    *
FROM (
    SELECT
        *
    FROM
        q_data
    WHERE
        temp_blks_written > 0
    ORDER BY
        temp_blks_written DESC
    LIMIT 100) a) b;
$sql$,
$sql$
WITH q_data AS (
    SELECT
        coalesce(queryid::text, 'insufficient-privileges-total') as tag_queryid,
        /*
         NB! if security conscious about exposing query texts replace the below expression with a dash ('-') OR
         use the stat_statements_no_query_text metric instead, created specifically for this use case.
         */
        array_to_string(array_agg(DISTINCT quote_ident(pg_get_userbyid(userid))), ',') AS users,
        sum(s.calls)::int8 AS calls,
        round(sum(s.total_time)::numeric, 3)::double precision AS total_time,
        sum(shared_blks_hit)::int8 AS shared_blks_hit,
        sum(shared_blks_read)::int8 AS shared_blks_read,
        sum(shared_blks_written)::int8 AS shared_blks_written,
        sum(shared_blks_dirtied)::int8 AS shared_blks_dirtied,
        sum(temp_blks_read)::int8 AS temp_blks_read,
        sum(temp_blks_written)::int8 AS temp_blks_written,
        round(sum(blk_read_time)::numeric, 3)::double precision AS blk_read_time,
        round(sum(blk_write_time)::numeric, 3)::double precision AS blk_write_time,
        max(query::varchar(8000)) AS query
    FROM
        pg_stat_statements s
    WHERE
        calls > 5
        AND total_time > 5
        AND dbid = (
            SELECT
                oid
            FROM
                pg_database
            WHERE
                datname = current_database())
            AND NOT upper(s.query::varchar(50))
            LIKE ANY (ARRAY['DEALLOCATE%',
                'SET %',
                'RESET %',
                'BEGIN%',
                'BEGIN;',
                'COMMIT%',
                'END%',
                'ROLLBACK%',
                'SHOW%'])
        GROUP BY
            queryid
)
SELECT (EXTRACT(epoch FROM now()) * 1e9)::int8 AS epoch_ns,
       b.tag_queryid,
       b.users,
       b.calls,
       b.total_time,
       b.shared_blks_hit,
       b.shared_blks_read,
       b.shared_blks_written,
       b.shared_blks_dirtied,
       b.temp_blks_read,
       b.temp_blks_written,
       b.blk_read_time,
       b.blk_write_time,
       ltrim(regexp_replace(b.query, E'[ \\t\\n\\r]+', ' ', 'g')) tag_query
FROM (
    SELECT
        *
    FROM (
        SELECT
            *
        FROM
            q_data
        WHERE
            total_time > 0
        ORDER BY
            total_time DESC
        LIMIT 100) a
UNION
SELECT
    *
FROM (
    SELECT
        *
    FROM
        q_data
    ORDER BY
        calls DESC
    LIMIT 100) a
UNION
SELECT
    *
FROM (
    SELECT
        *
    FROM
        q_data
    WHERE
        shared_blks_read > 0
    ORDER BY
        shared_blks_read DESC
    LIMIT 100) a
UNION
SELECT
    *
FROM (
    SELECT
        *
    FROM
        q_data
    WHERE
        shared_blks_written > 0
    ORDER BY
        shared_blks_written DESC
    LIMIT 100) a
UNION
SELECT
    *
FROM (
    SELECT
        *
    FROM
        q_data
    WHERE
        temp_blks_read > 0
    ORDER BY
        temp_blks_read DESC
    LIMIT 100) a
UNION
SELECT
    *
FROM (
    SELECT
        *
    FROM
        q_data
    WHERE
        temp_blks_written > 0
    ORDER BY
        temp_blks_written DESC
    LIMIT 100) a) b;
$sql$
);


insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_sql_su)
values (
'stat_statements',
13,
$sql$
WITH q_data AS (
    SELECT
        coalesce(queryid::text, 'insufficient-privileges-total') as tag_queryid,
        /*
         NB! if security conscious about exposing query texts replace the below expression with a dash ('-') OR
         use the stat_statements_no_query_text metric instead, created specifically for this use case.
         */
        array_to_string(array_agg(DISTINCT quote_ident(pg_get_userbyid(userid))), ',') AS users,
        sum(s.calls)::int8 AS calls,
        round(sum(s.total_exec_time)::numeric, 3)::double precision AS total_time,
        sum(shared_blks_hit)::int8 AS shared_blks_hit,
        sum(shared_blks_read)::int8 AS shared_blks_read,
        sum(shared_blks_written)::int8 AS shared_blks_written,
        sum(shared_blks_dirtied)::int8 AS shared_blks_dirtied,
        sum(temp_blks_read)::int8 AS temp_blks_read,
        sum(temp_blks_written)::int8 AS temp_blks_written,
        round(sum(blk_read_time)::numeric, 3)::double precision AS blk_read_time,
        round(sum(blk_write_time)::numeric, 3)::double precision AS blk_write_time,
        sum(wal_fpi)::int8 AS wal_fpi,
        sum(wal_bytes)::int8 AS wal_bytes,
        round(sum(s.total_plan_time)::numeric, 3)::double precision AS total_plan_time,
        max(query::varchar(8000)) AS query
    FROM
        get_stat_statements() s
    WHERE
        calls > 5
        AND total_exec_time > 5
        AND dbid = (
            SELECT
                oid
            FROM
                pg_database
            WHERE
                datname = current_database())
            AND NOT upper(s.query::varchar(50))
            LIKE ANY (ARRAY['DEALLOCATE%',
                'SET %',
                'RESET %',
                'BEGIN%',
                'BEGIN;',
                'COMMIT%',
                'END%',
                'ROLLBACK%',
                'SHOW%'])
        GROUP BY
            queryid
)
SELECT
    (EXTRACT(epoch FROM now()) * 1e9)::int8 AS epoch_ns,
    b.tag_queryid,
    b.users,
    b.calls,
    b.total_time,
    b.shared_blks_hit,
    b.shared_blks_read,
    b.shared_blks_written,
    b.shared_blks_dirtied,
    b.temp_blks_read,
    b.temp_blks_written,
    b.blk_read_time,
    b.blk_write_time,
    b.wal_fpi,
    b.wal_bytes,
    b.total_plan_time,
    ltrim(regexp_replace(b.query, E'[ \\t\\n\\r]+', ' ', 'g')) AS tag_query
FROM (
    SELECT
        *
    FROM (
        SELECT
            *
        FROM
            q_data
        WHERE
            total_time > 0
        ORDER BY
            total_time DESC
        LIMIT 100) a
UNION
SELECT
    *
FROM (
    SELECT
        *
    FROM
        q_data
    ORDER BY
        calls DESC
    LIMIT 100) a
UNION
SELECT
    *
FROM (
    SELECT
        *
    FROM
        q_data
    WHERE
        shared_blks_read > 0
    ORDER BY
        shared_blks_read DESC
    LIMIT 100) a
UNION
SELECT
    *
FROM (
    SELECT
        *
    FROM
        q_data
    WHERE
        shared_blks_written > 0
    ORDER BY
        shared_blks_written DESC
    LIMIT 100) a
UNION
SELECT
    *
FROM (
    SELECT
        *
    FROM
        q_data
    WHERE
        temp_blks_read > 0
    ORDER BY
        temp_blks_read DESC
    LIMIT 100) a
UNION
SELECT
    *
FROM (
    SELECT
        *
    FROM
        q_data
    WHERE
        temp_blks_written > 0
    ORDER BY
        temp_blks_written DESC
    LIMIT 100) a) b;
$sql$,
$sql$
WITH q_data AS (
    SELECT
        coalesce(queryid::text, 'insufficient-privileges-total') as tag_queryid,
        /*
         NB! if security conscious about exposing query texts replace the below expression with a dash ('-') OR
         use the stat_statements_no_query_text metric instead, created specifically for this use case.
         */
        array_to_string(array_agg(DISTINCT quote_ident(pg_get_userbyid(userid))), ',') AS users,
        sum(s.calls)::int8 AS calls,
        round(sum(s.total_exec_time)::numeric, 3)::double precision AS total_time,
        sum(shared_blks_hit)::int8 AS shared_blks_hit,
        sum(shared_blks_read)::int8 AS shared_blks_read,
        sum(shared_blks_written)::int8 AS shared_blks_written,
        sum(shared_blks_dirtied)::int8 AS shared_blks_dirtied,
        sum(temp_blks_read)::int8 AS temp_blks_read,
        sum(temp_blks_written)::int8 AS temp_blks_written,
        round(sum(blk_read_time)::numeric, 3)::double precision AS blk_read_time,
        round(sum(blk_write_time)::numeric, 3)::double precision AS blk_write_time,
        sum(wal_fpi)::int8 AS wal_fpi,
        sum(wal_bytes)::int8 AS wal_bytes,
        round(sum(s.total_plan_time)::numeric, 3)::double precision AS total_plan_time,
        max(query::varchar(8000)) AS query
    FROM
        pg_stat_statements s
    WHERE
        calls > 5
        AND total_exec_time > 5
        AND dbid = (
            SELECT
                oid
            FROM
                pg_database
            WHERE
                datname = current_database())
            AND NOT upper(s.query::varchar(50))
            LIKE ANY (ARRAY['DEALLOCATE%',
                'SET %',
                'RESET %',
                'BEGIN%',
                'BEGIN;',
                'COMMIT%',
                'END%',
                'ROLLBACK%',
                'SHOW%'])
        GROUP BY
            queryid
)
SELECT
    (EXTRACT(epoch FROM now()) * 1e9)::int8 AS epoch_ns,
    b.tag_queryid,
    b.users,
    b.calls,
    b.total_time,
    b.shared_blks_hit,
    b.shared_blks_read,
    b.shared_blks_written,
    b.shared_blks_dirtied,
    b.temp_blks_read,
    b.temp_blks_written,
    b.blk_read_time,
    b.blk_write_time,
    b.wal_fpi,
    b.wal_bytes,
    b.total_plan_time,
    ltrim(regexp_replace(b.query, E'[ \\t\\n\\r]+', ' ', 'g')) AS tag_query
FROM (
    SELECT
        *
    FROM (
        SELECT
            *
        FROM
            q_data
        WHERE
            total_time > 0
        ORDER BY
            total_time DESC
        LIMIT 100) a
UNION
SELECT
    *
FROM (
    SELECT
        *
    FROM
        q_data
    ORDER BY
        calls DESC
    LIMIT 100) a
UNION
SELECT
    *
FROM (
    SELECT
        *
    FROM
        q_data
    WHERE
        shared_blks_read > 0
    ORDER BY
        shared_blks_read DESC
    LIMIT 100) a
UNION
SELECT
    *
FROM (
    SELECT
        *
    FROM
        q_data
    WHERE
        shared_blks_written > 0
    ORDER BY
        shared_blks_written DESC
    LIMIT 100) a
UNION
SELECT
    *
FROM (
    SELECT
        *
    FROM
        q_data
    WHERE
        temp_blks_read > 0
    ORDER BY
        temp_blks_read DESC
    LIMIT 100) a
UNION
SELECT
    *
FROM (
    SELECT
        *
    FROM
        q_data
    WHERE
        temp_blks_written > 0
    ORDER BY
        temp_blks_written DESC
    LIMIT 100) a) b;
$sql$
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_sql_su)
values (
'stat_statements',
15,
$sql$
WITH q_data AS (
    SELECT
        queryid::text AS tag_queryid,
        /*
         NB! if security conscious about exposing query texts replace the below expression with a dash ('-') OR
         use the stat_statements_no_query_text metric instead, created specifically for this use case.
         */
        array_to_string(array_agg(DISTINCT quote_ident(pg_get_userbyid(userid))), ',') AS users,
        sum(s.calls)::int8 AS calls,
        round(sum(s.total_exec_time)::numeric, 3)::double precision AS total_time,
        sum(shared_blks_hit)::int8 AS shared_blks_hit,
        sum(shared_blks_read)::int8 AS shared_blks_read,
        sum(shared_blks_written)::int8 AS shared_blks_written,
        sum(shared_blks_dirtied)::int8 AS shared_blks_dirtied,
        sum(temp_blks_read)::int8 AS temp_blks_read,
        sum(temp_blks_written)::int8 AS temp_blks_written,
        round(sum(blk_read_time)::numeric, 3)::double precision AS blk_read_time,
        round(sum(blk_write_time)::numeric, 3)::double precision AS blk_write_time,
        round(sum(temp_blk_read_time)::numeric, 3)::double precision AS temp_blk_read_time,
        round(sum(temp_blk_write_time)::numeric, 3)::double precision AS temp_blk_write_time,
        sum(wal_fpi)::int8 AS wal_fpi,
        sum(wal_bytes)::int8 AS wal_bytes,
        round(sum(s.total_plan_time)::numeric, 3)::double precision AS total_plan_time,
        max(query::varchar(8000)) AS query
    FROM
        get_stat_statements() s
    WHERE
        calls > 5
        AND total_exec_time > 5
        AND dbid = (
            SELECT
                oid
            FROM
                pg_database
            WHERE
                datname = current_database())
            AND NOT upper(s.query::varchar(50))
            LIKE ANY (ARRAY['DEALLOCATE%',
                'SET %',
                'RESET %',
                'BEGIN%',
                'BEGIN;',
                'COMMIT%',
                'END%',
                'ROLLBACK%',
                'SHOW%'])
        GROUP BY
            queryid
)
SELECT
    (EXTRACT(epoch FROM now()) * 1e9)::int8 AS epoch_ns,
    b.tag_queryid,
    b.users,
    b.calls,
    b.total_time,
    b.shared_blks_hit,
    b.shared_blks_read,
    b.shared_blks_written,
    b.shared_blks_dirtied,
    b.temp_blks_read,
    b.temp_blks_written,
    b.blk_read_time,
    b.blk_write_time,
    b.temp_blk_read_time,
    b.temp_blk_write_time,
    b.wal_fpi,
    b.wal_bytes,
    b.total_plan_time,
    ltrim(regexp_replace(b.query, E'[ \\t\\n\\r]+', ' ', 'g')) AS tag_query
FROM (
    SELECT
        *
    FROM (
        SELECT
            *
        FROM
            q_data
        WHERE
            total_time > 0
        ORDER BY
            total_time DESC
        LIMIT 100) a
UNION
SELECT
    *
FROM (
    SELECT
        *
    FROM
        q_data
    ORDER BY
        calls DESC
    LIMIT 100) a
UNION
SELECT
    *
FROM (
    SELECT
        *
    FROM
        q_data
    WHERE
        shared_blks_read > 0
    ORDER BY
        shared_blks_read DESC
    LIMIT 100) a
UNION
SELECT
    *
FROM (
    SELECT
        *
    FROM
        q_data
    WHERE
        shared_blks_written > 0
    ORDER BY
        shared_blks_written DESC
    LIMIT 100) a
UNION
SELECT
    *
FROM (
    SELECT
        *
    FROM
        q_data
    WHERE
        temp_blks_read > 0
    ORDER BY
        temp_blks_read DESC
    LIMIT 100) a
UNION
SELECT
    *
FROM (
    SELECT
        *
    FROM
        q_data
    WHERE
        temp_blks_written > 0
    ORDER BY
        temp_blks_written DESC
    LIMIT 100) a) b;
$sql$,
$sql$
WITH q_data AS (
    SELECT
        queryid::text AS tag_queryid,
        /*
         NB! if security conscious about exposing query texts replace the below expression with a dash ('-') OR
         use the stat_statements_no_query_text metric instead, created specifically for this use case.
         */
        array_to_string(array_agg(DISTINCT quote_ident(pg_get_userbyid(userid))), ',') AS users,
        sum(s.calls)::int8 AS calls,
        round(sum(s.total_exec_time)::numeric, 3)::double precision AS total_time,
        sum(shared_blks_hit)::int8 AS shared_blks_hit,
        sum(shared_blks_read)::int8 AS shared_blks_read,
        sum(shared_blks_written)::int8 AS shared_blks_written,
        sum(shared_blks_dirtied)::int8 AS shared_blks_dirtied,
        sum(temp_blks_read)::int8 AS temp_blks_read,
        sum(temp_blks_written)::int8 AS temp_blks_written,
        round(sum(blk_read_time)::numeric, 3)::double precision AS blk_read_time,
        round(sum(blk_write_time)::numeric, 3)::double precision AS blk_write_time,
        round(sum(temp_blk_read_time)::numeric, 3)::double precision AS temp_blk_read_time,
        round(sum(temp_blk_write_time)::numeric, 3)::double precision AS temp_blk_write_time,
        sum(wal_fpi)::int8 AS wal_fpi,
        sum(wal_bytes)::int8 AS wal_bytes,
        round(sum(s.total_plan_time)::numeric, 3)::double precision AS total_plan_time,
        max(query::varchar(8000)) AS query
    FROM
        pg_stat_statements s
    WHERE
        calls > 5
        AND total_exec_time > 5
        AND dbid = (
            SELECT
                oid
            FROM
                pg_database
            WHERE
                datname = current_database())
            AND NOT upper(s.query::varchar(50))
            LIKE ANY (ARRAY['DEALLOCATE%',
                'SET %',
                'RESET %',
                'BEGIN%',
                'BEGIN;',
                'COMMIT%',
                'END%',
                'ROLLBACK%',
                'SHOW%'])
        GROUP BY
            queryid
)
SELECT
    (EXTRACT(epoch FROM now()) * 1e9)::int8 AS epoch_ns,
    b.tag_queryid,
    b.users,
    b.calls,
    b.total_time,
    b.shared_blks_hit,
    b.shared_blks_read,
    b.shared_blks_written,
    b.shared_blks_dirtied,
    b.temp_blks_read,
    b.temp_blks_written,
    b.blk_read_time,
    b.blk_write_time,
    b.temp_blk_read_time,
    b.temp_blk_write_time,
    b.wal_fpi,
    b.wal_bytes,
    b.total_plan_time,
    ltrim(regexp_replace(b.query, E'[ \\t\\n\\r]+', ' ', 'g')) AS tag_query
FROM (
    SELECT
        *
    FROM (
        SELECT
            *
        FROM
            q_data
        WHERE
            total_time > 0
        ORDER BY
            total_time DESC
        LIMIT 100) a
UNION
SELECT
    *
FROM (
    SELECT
        *
    FROM
        q_data
    ORDER BY
        calls DESC
    LIMIT 100) a
UNION
SELECT
    *
FROM (
    SELECT
        *
    FROM
        q_data
    WHERE
        shared_blks_read > 0
    ORDER BY
        shared_blks_read DESC
    LIMIT 100) a
UNION
SELECT
    *
FROM (
    SELECT
        *
    FROM
        q_data
    WHERE
        shared_blks_written > 0
    ORDER BY
        shared_blks_written DESC
    LIMIT 100) a
UNION
SELECT
    *
FROM (
    SELECT
        *
    FROM
        q_data
    WHERE
        temp_blks_read > 0
    ORDER BY
        temp_blks_read DESC
    LIMIT 100) a
UNION
SELECT
    *
FROM (
    SELECT
        *
    FROM
        q_data
    WHERE
        temp_blks_written > 0
    ORDER BY
        temp_blks_written DESC
    LIMIT 100) a) b;
$sql$
);


/* stat_statements_no_query_text - the same as normal ss but leaving out query texts for security */

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_sql_su)
values (
'stat_statements_no_query_text',
9.2,
$sql$
with q_data as (
  select
    (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
    (regexp_replace(md5(query), E'\\D', '', 'g'))::varchar(10)::int8 as tag_queryid,
    '-'::text as tag_query,
    array_to_string(array_agg(distinct quote_ident(pg_get_userbyid(userid))), ',') as users,
    sum(s.calls)::int8 as calls,
    round(sum(s.total_time)::numeric, 3)::double precision as total_time,
    sum(shared_blks_hit)::int8 as shared_blks_hit,
    sum(shared_blks_read)::int8 as shared_blks_read,
    sum(shared_blks_written)::int8 as shared_blks_written,
    sum(shared_blks_dirtied)::int8 as shared_blks_dirtied,
    sum(temp_blks_read)::int8 as temp_blks_read,
    sum(temp_blks_written)::int8 as temp_blks_written,
    round(sum(blk_read_time)::numeric, 3)::double precision as blk_read_time,
    round(sum(blk_write_time)::numeric, 3)::double precision as blk_write_time
  from
    get_stat_statements() s
  where
    calls > 5
    and total_time > 0
    and dbid = (select oid from pg_database where datname = current_database())
    and not upper(s.query) like any (array['DEALLOCATE%', 'SET %', 'RESET %', 'BEGIN%', 'BEGIN;',
      'COMMIT%', 'END%', 'ROLLBACK%', 'SHOW%'])
  group by
    tag_queryid
)
select * from (
  select
    *
  from
    q_data
  where
    total_time > 0
  order by
    total_time desc
  limit 100
) a
union
select * from (
  select
    *
  from
    q_data
  order by
    calls desc
  limit 100
) a
union
select * from (
  select
    *
  from
    q_data
  where
    shared_blks_read > 0
  order by
    shared_blks_read desc
  limit 100
) a
union
select * from (
  select
    *
  from
    q_data
  where
    shared_blks_written > 0
  order by
    shared_blks_written desc
  limit 100
) a
union
select * from (
  select
    *
  from
    q_data
  where
    temp_blks_read > 0
  order by
    temp_blks_read desc
  limit 100
) a
union
select * from (
  select
    *
  from
    q_data
  where
    temp_blks_written > 0
  order by
    temp_blks_written desc
  limit 100
) a;
$sql$,
$sql$
with q_data as (
  select
    (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
    (regexp_replace(md5(query), E'\\D', '', 'g'))::varchar(10)::int8 as tag_queryid,
    '-'::text as tag_query,
    array_to_string(array_agg(distinct quote_ident(pg_get_userbyid(userid))), ',') as users,
    sum(s.calls)::int8 as calls,
    round(sum(s.total_time)::numeric, 3)::double precision as total_time,
    sum(shared_blks_hit)::int8 as shared_blks_hit,
    sum(shared_blks_read)::int8 as shared_blks_read,
    sum(shared_blks_written)::int8 as shared_blks_written,
    sum(shared_blks_dirtied)::int8 as shared_blks_dirtied,
    sum(temp_blks_read)::int8 as temp_blks_read,
    sum(temp_blks_written)::int8 as temp_blks_written,
    round(sum(blk_read_time)::numeric, 3)::double precision as blk_read_time,
    round(sum(blk_write_time)::numeric, 3)::double precision as blk_write_time
  from
    pg_stat_statements s
  where
    calls > 5
    and total_time > 0
    and dbid = (select oid from pg_database where datname = current_database())
    and not upper(s.query) like any (array['DEALLOCATE%', 'SET %', 'RESET %', 'BEGIN%', 'BEGIN;',
      'COMMIT%', 'END%', 'ROLLBACK%', 'SHOW%'])
  group by
    tag_queryid
)
select * from (
  select
    *
  from
    q_data
  where
    total_time > 0
  order by
    total_time desc
  limit 100
) a
union
select * from (
  select
    *
  from
    q_data
  order by
    calls desc
  limit 100
) a
union
select * from (
  select
    *
  from
    q_data
  where
    shared_blks_read > 0
  order by
    shared_blks_read desc
  limit 100
) a
union
select * from (
  select
    *
  from
    q_data
  where
    shared_blks_written > 0
  order by
    shared_blks_written desc
  limit 100
) a
union
select * from (
  select
    *
  from
    q_data
  where
    temp_blks_read > 0
  order by
    temp_blks_read desc
  limit 100
) a
union
select * from (
  select
    *
  from
    q_data
  where
    temp_blks_written > 0
  order by
    temp_blks_written desc
  limit 100
) a;
$sql$
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_sql_su)
values (
'stat_statements_no_query_text',
9.4,
$sql$
with q_data as (
  select
    (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
    coalesce(queryid::text, 'insufficient-privileges-total') as tag_queryid,
    '-'::text as tag_query,
    array_to_string(array_agg(distinct quote_ident(pg_get_userbyid(userid))), ',') as users,
    sum(s.calls)::int8 as calls,
    round(sum(s.total_time)::numeric, 3)::double precision as total_time,
    sum(shared_blks_hit)::int8 as shared_blks_hit,
    sum(shared_blks_read)::int8 as shared_blks_read,
    sum(shared_blks_written)::int8 as shared_blks_written,
    sum(shared_blks_dirtied)::int8 as shared_blks_dirtied,
    sum(temp_blks_read)::int8 as temp_blks_read,
    sum(temp_blks_written)::int8 as temp_blks_written,
    round(sum(blk_read_time)::numeric, 3)::double precision as blk_read_time,
    round(sum(blk_write_time)::numeric, 3)::double precision as blk_write_time
  from
    get_stat_statements() s
  where
    calls > 5
    and total_time > 0
    and dbid = (select oid from pg_database where datname = current_database())
    and not upper(s.query) like any (array['DEALLOCATE%', 'SET %', 'RESET %', 'BEGIN%', 'BEGIN;',
      'COMMIT%', 'END%', 'ROLLBACK%', 'SHOW%'])
  group by
    queryid
)
select * from (
  select
    *
  from
    q_data
  where
    total_time > 0
  order by
    total_time desc
  limit 100
) a
union
select * from (
  select
    *
  from
    q_data
  order by
    calls desc
  limit 100
) a
union
select * from (
  select
    *
  from
    q_data
  where
    shared_blks_read > 0
  order by
    shared_blks_read desc
  limit 100
) a
union
select * from (
  select
    *
  from
    q_data
  where
    shared_blks_written > 0
  order by
    shared_blks_written desc
  limit 100
) a
union
select * from (
  select
    *
  from
    q_data
  where
    temp_blks_read > 0
  order by
    temp_blks_read desc
  limit 100
) a
union
select * from (
  select
    *
  from
    q_data
  where
    temp_blks_written > 0
  order by
    temp_blks_written desc
  limit 100
) a;
$sql$,
$sql$
with q_data as (
  select
    (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
    coalesce(queryid::text, 'insufficient-privileges-total') as tag_queryid,
    '-'::text as tag_query,
    array_to_string(array_agg(distinct quote_ident(pg_get_userbyid(userid))), ',') as users,
    sum(s.calls)::int8 as calls,
    round(sum(s.total_time)::numeric, 3)::double precision as total_time,
    sum(shared_blks_hit)::int8 as shared_blks_hit,
    sum(shared_blks_read)::int8 as shared_blks_read,
    sum(shared_blks_written)::int8 as shared_blks_written,
    sum(shared_blks_dirtied)::int8 as shared_blks_dirtied,
    sum(temp_blks_read)::int8 as temp_blks_read,
    sum(temp_blks_written)::int8 as temp_blks_written,
    round(sum(blk_read_time)::numeric, 3)::double precision as blk_read_time,
    round(sum(blk_write_time)::numeric, 3)::double precision as blk_write_time
  from
    pg_stat_statements s
  where
    calls > 5
    and total_time > 0
    and dbid = (select oid from pg_database where datname = current_database())
    and not upper(s.query) like any (array['DEALLOCATE%', 'SET %', 'RESET %', 'BEGIN%', 'BEGIN;',
      'COMMIT%', 'END%', 'ROLLBACK%', 'SHOW%'])
  group by
    queryid
)
select * from (
  select
    *
  from
    q_data
  where
    total_time > 0
  order by
    total_time desc
  limit 100
) a
union
select * from (
  select
    *
  from
    q_data
  order by
    calls desc
  limit 100
) a
union
select * from (
  select
    *
  from
    q_data
  where
    shared_blks_read > 0
  order by
    shared_blks_read desc
  limit 100
) a
union
select * from (
  select
    *
  from
    q_data
  where
    shared_blks_written > 0
  order by
    shared_blks_written desc
  limit 100
) a
union
select * from (
  select
    *
  from
    q_data
  where
    temp_blks_read > 0
  order by
    temp_blks_read desc
  limit 100
) a
union
select * from (
  select
    *
  from
    q_data
  where
    temp_blks_written > 0
  order by
    temp_blks_written desc
  limit 100
) a;
$sql$
);


insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_sql_su)
values (
'stat_statements_no_query_text',
13,
$sql$
with q_data as (
  select
    (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
    coalesce(queryid::text, 'insufficient-privileges-total') as tag_queryid,
    '-' as tag_query,
    array_to_string(array_agg(distinct quote_ident(pg_get_userbyid(userid))), ',') as users,
    sum(s.calls)::int8 as calls,
    round(sum(s.total_exec_time)::numeric, 3)::double precision as total_time,
    sum(shared_blks_hit)::int8 as shared_blks_hit,
    sum(shared_blks_read)::int8 as shared_blks_read,
    sum(shared_blks_written)::int8 as shared_blks_written,
    sum(shared_blks_dirtied)::int8 as shared_blks_dirtied,
    sum(temp_blks_read)::int8 as temp_blks_read,
    sum(temp_blks_written)::int8 as temp_blks_written,
    round(sum(blk_read_time)::numeric, 3)::double precision as blk_read_time,
    round(sum(blk_write_time)::numeric, 3)::double precision as blk_write_time,
    sum(wal_fpi)::int8 as wal_fpi,
    sum(wal_bytes)::int8 as wal_bytes,
    round(sum(s.total_plan_time)::numeric, 3)::double precision as total_plan_time
  from
    get_stat_statements() s
  where
    calls > 5
    and total_exec_time > 0
    and dbid = (select oid from pg_database where datname = current_database())
    and not upper(s.query) like any (array['DEALLOCATE%', 'SET %', 'RESET %', 'BEGIN%', 'BEGIN;',
      'COMMIT%', 'END%', 'ROLLBACK%', 'SHOW%'])
  group by
    queryid
)
select * from (
  select
    *
  from
    q_data
  where
    total_time > 0
  order by
    total_time desc
  limit 100
) a
union
select * from (
  select
    *
  from
    q_data
  order by
    calls desc
  limit 100
) a
union
select * from (
  select
    *
  from
    q_data
  where
    shared_blks_read > 0
  order by
    shared_blks_read desc
  limit 100
) a
union
select * from (
  select
    *
  from
    q_data
  where
    shared_blks_written > 0
  order by
    shared_blks_written desc
  limit 100
) a
union
select * from (
  select
    *
  from
    q_data
  where
    temp_blks_read > 0
  order by
    temp_blks_read desc
  limit 100
) a
union
select * from (
  select
    *
  from
    q_data
  where
    temp_blks_written > 0
  order by
    temp_blks_written desc
  limit 100
) a;
$sql$,
$sql$
with q_data as (
  select
    (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
    coalesce(queryid::text, 'insufficient-privileges-total') as tag_queryid,
    '-' as tag_query,
    array_to_string(array_agg(distinct quote_ident(pg_get_userbyid(userid))), ',') as users,
    sum(s.calls)::int8 as calls,
    round(sum(s.total_exec_time)::numeric, 3)::double precision as total_time,
    sum(shared_blks_hit)::int8 as shared_blks_hit,
    sum(shared_blks_read)::int8 as shared_blks_read,
    sum(shared_blks_written)::int8 as shared_blks_written,
    sum(shared_blks_dirtied)::int8 as shared_blks_dirtied,
    sum(temp_blks_read)::int8 as temp_blks_read,
    sum(temp_blks_written)::int8 as temp_blks_written,
    round(sum(blk_read_time)::numeric, 3)::double precision as blk_read_time,
    round(sum(blk_write_time)::numeric, 3)::double precision as blk_write_time,
    sum(wal_fpi)::int8 as wal_fpi,
    sum(wal_bytes)::int8 as wal_bytes,
    round(sum(s.total_plan_time)::numeric, 3)::double precision as total_plan_time
  from
    pg_stat_statements s
  where
    calls > 5
    and total_exec_time > 0
    and dbid = (select oid from pg_database where datname = current_database())
    and not upper(s.query) like any (array['DEALLOCATE%', 'SET %', 'RESET %', 'BEGIN%', 'BEGIN;',
      'COMMIT%', 'END%', 'ROLLBACK%', 'SHOW%'])
  group by
    queryid
)
select * from (
  select
    *
  from
    q_data
  where
    total_time > 0
  order by
    total_time desc
  limit 100
) a
union
select * from (
  select
    *
  from
    q_data
  order by
    calls desc
  limit 100
) a
union
select * from (
  select
    *
  from
    q_data
  where
    shared_blks_read > 0
  order by
    shared_blks_read desc
  limit 100
) a
union
select * from (
  select
    *
  from
    q_data
  where
    shared_blks_written > 0
  order by
    shared_blks_written desc
  limit 100
) a
union
select * from (
  select
    *
  from
    q_data
  where
    temp_blks_read > 0
  order by
    temp_blks_read desc
  limit 100
) a
union
select * from (
  select
    *
  from
    q_data
  where
    temp_blks_written > 0
  order by
    temp_blks_written desc
  limit 100
) a;
$sql$
);


insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_sql_su)
values (
'stat_statements_no_query_text',
15,
$sql$
with q_data as (
  select
    (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
    '-' as tag_query,
    queryid::text as tag_queryid,
    array_to_string(array_agg(distinct quote_ident(pg_get_userbyid(userid))), ',') as users,
    sum(s.calls)::int8 as calls,
    round(sum(s.total_exec_time)::numeric, 3)::double precision as total_time,
    sum(shared_blks_hit)::int8 as shared_blks_hit,
    sum(shared_blks_read)::int8 as shared_blks_read,
    sum(shared_blks_written)::int8 as shared_blks_written,
    sum(shared_blks_dirtied)::int8 as shared_blks_dirtied,
    sum(temp_blks_read)::int8 as temp_blks_read,
    sum(temp_blks_written)::int8 as temp_blks_written,
    round(sum(blk_read_time)::numeric, 3)::double precision as blk_read_time,
    round(sum(blk_write_time)::numeric, 3)::double precision as blk_write_time,
    round(sum(temp_blk_read_time)::numeric, 3)::double precision as temp_blk_read_time,
    round(sum(temp_blk_write_time)::numeric, 3)::double precision as temp_blk_write_time,
    sum(wal_fpi)::int8 as wal_fpi,
    sum(wal_bytes)::int8 as wal_bytes,
    round(sum(s.total_plan_time)::numeric, 3)::double precision as total_plan_time
  from
    get_stat_statements() s
  where
    calls > 5
    and total_exec_time > 0
    and dbid = (select oid from pg_database where datname = current_database())
    and not upper(s.query) like any (array['DEALLOCATE%', 'SET %', 'RESET %', 'BEGIN%', 'BEGIN;',
      'COMMIT%', 'END%', 'ROLLBACK%', 'SHOW%'])
  group by
    queryid
)
select * from (
  select
    *
  from
    q_data
  where
    total_time > 0
  order by
    total_time desc
  limit 100
) a
union
select * from (
  select
    *
  from
    q_data
  order by
    calls desc
  limit 100
) a
union
select * from (
  select
    *
  from
    q_data
  where
    shared_blks_read > 0
  order by
    shared_blks_read desc
  limit 100
) a
union
select * from (
  select
    *
  from
    q_data
  where
    shared_blks_written > 0
  order by
    shared_blks_written desc
  limit 100
) a
union
select * from (
  select
    *
  from
    q_data
  where
    temp_blks_read > 0
  order by
    temp_blks_read desc
  limit 100
) a
union
select * from (
  select
    *
  from
    q_data
  where
    temp_blks_written > 0
  order by
    temp_blks_written desc
  limit 100
) a;
$sql$,
$sql$
with q_data as (
  select
    (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
    '-' as tag_query,
    queryid::text as tag_queryid,
    array_to_string(array_agg(distinct quote_ident(pg_get_userbyid(userid))), ',') as users,
    sum(s.calls)::int8 as calls,
    round(sum(s.total_exec_time)::numeric, 3)::double precision as total_time,
    sum(shared_blks_hit)::int8 as shared_blks_hit,
    sum(shared_blks_read)::int8 as shared_blks_read,
    sum(shared_blks_written)::int8 as shared_blks_written,
    sum(shared_blks_dirtied)::int8 as shared_blks_dirtied,
    sum(temp_blks_read)::int8 as temp_blks_read,
    sum(temp_blks_written)::int8 as temp_blks_written,
    round(sum(blk_read_time)::numeric, 3)::double precision as blk_read_time,
    round(sum(blk_write_time)::numeric, 3)::double precision as blk_write_time,
    round(sum(temp_blk_read_time)::numeric, 3)::double precision as temp_blk_read_time,
    round(sum(temp_blk_write_time)::numeric, 3)::double precision as temp_blk_write_time,
    sum(wal_fpi) as wal_fpi,
    sum(wal_bytes) as wal_bytes,
    round(sum(s.total_plan_time)::numeric, 3)::double precision as total_plan_time
  from
    pg_stat_statements s
  where
    calls > 5
    and total_exec_time > 0
    and dbid = (select oid from pg_database where datname = current_database())
    and not upper(s.query) like any (array['DEALLOCATE%', 'SET %', 'RESET %', 'BEGIN%', 'BEGIN;',
      'COMMIT%', 'END%', 'ROLLBACK%', 'SHOW%'])
  group by
    queryid
)
select * from (
  select
    *
  from
    q_data
  where
    total_time > 0
  order by
    total_time desc
  limit 100
) a
union
select * from (
  select
    *
  from
    q_data
  order by
    calls desc
  limit 100
) a
union
select * from (
  select
    *
  from
    q_data
  where
    shared_blks_read > 0
  order by
    shared_blks_read desc
  limit 100
) a
union
select * from (
  select
    *
  from
    q_data
  where
    shared_blks_written > 0
  order by
    shared_blks_written desc
  limit 100
) a
union
select * from (
  select
    *
  from
    q_data
  where
    temp_blks_read > 0
  order by
    temp_blks_read desc
  limit 100
) a
union
select * from (
  select
    *
  from
    q_data
  where
    temp_blks_written > 0
  order by
    temp_blks_written desc
  limit 100
) a;
$sql$
);


/* stat_statements_calls - enables to show QPS queries per second. "calls" works without the above wrapper also */

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql)
values (
'stat_statements_calls',
9.2,
$sql$
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  coalesce(sum(calls), 0)::int8 as calls,
  coalesce(round(sum(total_time)::numeric, 3), 0)::float8 as total_time
from
  pg_stat_statements
where
  dbid = (select oid from pg_database where datname = current_database())
;
$sql$
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql)
values (
'stat_statements_calls',
13,
$sql$
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  coalesce(sum(calls), 0)::int8 as calls,
  coalesce(round(sum(total_exec_time)::numeric, 3), 0)::float8 as total_time,
  round(sum(total_plan_time)::numeric, 3)::double precision as total_plan_time
from
  pg_stat_statements
where
  dbid = (select oid from pg_database where datname = current_database())
;
$sql$
);


/* buffercache_by_db */
insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs)
values (
'buffercache_by_db',
9.2,
$sql$
SELECT
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  datname as tag_database,
  count(*) * (current_setting('block_size')::int8) as size_b
FROM
  pg_buffercache AS b,
  pg_database AS d
WHERE
  d.oid = b.reldatabase
GROUP BY
  datname;
$sql$,
'{"prometheus_gauge_columns": ["size_b"]}'
);

/* buffercache_by_type */
insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs)
values (
'buffercache_by_type',
9.2,
$sql$
SELECT
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  CASE
    WHEN relkind = 'r' THEN 'Table'   -- TODO all relkinds covered?
    WHEN relkind = 'i' THEN 'Index'
    WHEN relkind = 't' THEN 'Toast'
    WHEN relkind = 'm' THEN 'Materialized view'
    ELSE 'Other'
  END as tag_relkind,
  count(*) * (current_setting('block_size')::int8) as size_b
FROM
  pg_buffercache AS b,
  pg_class AS d
WHERE
  d.oid = b.relfilenode
GROUP BY
  relkind;
$sql$,
'{"prometheus_gauge_columns": ["size_b"]}'
);


/* stat_ssl */
insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_sql_su)
values (
'stat_ssl',
9.5,
$sql$
select /* pgwatch2_generated */
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  count(*) as total,
  count(*) FILTER (WHERE ssl) as "on",
  count(*) FILTER (WHERE NOT ssl) as "off"
FROM
  pg_stat_ssl AS s,
  get_stat_activity() AS a
WHERE
  a.pid = s.pid
  AND a.datname = current_database()
  AND a.pid <> pg_backend_pid()
  AND NOT (a.client_addr = '127.0.0.1' OR client_port = -1);
$sql$,
$sql$
select /* pgwatch2_generated */
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  count(*) as total,
  count(*) FILTER (WHERE ssl) as "on",
  count(*) FILTER (WHERE NOT ssl) as "off"
FROM
  pg_stat_ssl AS s,
  pg_stat_activity AS a
WHERE
  a.pid = s.pid
  AND a.datname = current_database()
  AND a.pid <> pg_backend_pid()
  AND NOT (a.client_addr = '127.0.0.1' OR client_port = -1);
$sql$
);


/* database_conflicts */
insert into pgwatch2.metric(m_name, m_pg_version_from, m_standby_only, m_sql)
values (
'database_conflicts',
9.2,
true,
$sql$
SELECT
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  confl_tablespace,
  confl_lock,
  confl_snapshot,
  confl_bufferpin,
  confl_deadlock
FROM
  pg_stat_database_conflicts
WHERE
  datname = current_database();
$sql$
);


/* locks - counts only */

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs)
values (
'locks',
9.0,
$sql$
WITH q_locks AS (
  select
    *
  from
    pg_locks
  where
    pid != pg_backend_pid()
    and database = (select oid from pg_database where datname = current_database())
)
SELECT
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  locktypes AS tag_locktype,
  coalesce((select count(*) FROM q_locks WHERE locktype = locktypes), 0) AS count
FROM
  unnest('{relation, extend, page, tuple, transactionid, virtualxid, object, userlock, advisory}'::text[]) locktypes;
$sql$,
'{"prometheus_gauge_columns": ["count"]}'
);

/* locks - counts only */

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs)
values (
'locks_mode',
9.0,
$sql$
WITH q_locks AS (
  select
    *
  from
    pg_locks
  where
    pid != pg_backend_pid()
    and database = (select oid from pg_database where datname = current_database())
)
SELECT
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  lockmodes AS tag_lockmode,
  coalesce((select count(*) FROM q_locks WHERE mode = lockmodes), 0) AS count
FROM
  unnest('{AccessShareLock, ExclusiveLock, RowShareLock, RowExclusiveLock, ShareLock, ShareRowExclusiveLock,  AccessExclusiveLock, ShareUpdateExclusiveLock}'::text[]) lockmodes;
$sql$,
'{"prometheus_gauge_columns": ["count"]}'
);


/* blocking_locks - based on https://wiki.postgresql.org/wiki/Lock_dependency_information.
 needs fast intervals though as locks are quite volatile normally, thus could be costly */
-- not usable for Prometheus
insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_sql_su)
values (
'blocking_locks',
9.2,
$sql$
SELECT
    (extract(epoch from now()) * 1e9)::int8 AS epoch_ns,
    waiting.locktype           AS tag_waiting_locktype,
    waiting_stm.usename::text  AS tag_waiting_user,
    coalesce(waiting.mode, 'null'::text) AS tag_waiting_mode,
    coalesce(waiting.relation::regclass::text, 'null') AS tag_waiting_table,
    waiting_stm.query          AS waiting_query,
    waiting.pid                AS waiting_pid,
    other.locktype             AS other_locktype,
    other.relation::regclass::text   AS other_table,
    other_stm.query            AS other_query,
    other.mode                 AS other_mode,
    other.pid                  AS other_pid,
    other_stm.usename::text    AS other_user
FROM
    pg_catalog.pg_locks AS waiting
JOIN
    get_stat_activity() AS waiting_stm
    ON (
        waiting_stm.pid = waiting.pid
    )
JOIN
    pg_catalog.pg_locks AS other
    ON (
        (
            waiting."database" = other."database"
        AND waiting.relation  = other.relation
        )
        OR waiting.transactionid = other.transactionid
    )
JOIN
    get_stat_activity() AS other_stm
    ON (
        other_stm.pid = other.pid
    )
WHERE
    NOT waiting.GRANTED
AND
    waiting.pid <> other.pid
AND
    other.GRANTED
AND
    waiting_stm.datname = current_database();
$sql$,
$sql$
WITH sa_snapshot AS (
  select * from pg_stat_activity
  where datname = current_database()
  and not query like 'autovacuum:%'
  and pid != pg_backend_pid()
)
SELECT
    (extract(epoch from now()) * 1e9)::int8 AS epoch_ns,
    waiting.locktype           AS tag_waiting_locktype,
    waiting_stm.usename::text  AS tag_waiting_user,
    coalesce(waiting.mode, 'null'::text) AS tag_waiting_mode,
    coalesce(waiting.relation::regclass::text, 'null') AS tag_waiting_table,
    waiting_stm.query          AS waiting_query,
    waiting.pid                AS waiting_pid,
    other.locktype             AS other_locktype,
    other.relation::regclass::text   AS other_table,
    other_stm.query            AS other_query,
    other.mode                 AS other_mode,
    other.pid                  AS other_pid,
    other_stm.usename::text    AS other_user
FROM
    pg_catalog.pg_locks AS waiting
JOIN
    sa_snapshot AS waiting_stm
    ON (
        waiting_stm.pid = waiting.pid
    )
JOIN
    pg_catalog.pg_locks AS other
    ON (
        (
            waiting."database" = other."database"
        AND waiting.relation  = other.relation
        )
        OR waiting.transactionid = other.transactionid
    )
JOIN
    sa_snapshot AS other_stm
    ON (
        other_stm.pid = other.pid
    )
WHERE
    NOT waiting.GRANTED
AND
    waiting.pid <> other.pid
AND
    other.GRANTED
AND
    waiting_stm.datname = current_database();
$sql$
);


/* approx. bloat - needs pgstattuple extension! superuser or pg_stat_scan_tables/pg_monitor builtin role required */
insert into pgwatch2.metric(m_name, m_pg_version_from, m_master_only, m_sql, m_column_attrs)
values (
'table_bloat_approx_stattuple',
9.5,
true,
$sql$
/* NB! accessing pgstattuple_approx directly requires superuser or pg_stat_scan_tables/pg_monitor builtin roles */
select
  (extract(epoch from now()) * 1e9)::int8 AS epoch_ns,
  quote_ident(n.nspname)||'.'||quote_ident(c.relname) as tag_full_table_name,
  approx_free_percent,
  approx_free_space as approx_free_space_b,
  approx_tuple_count,
  dead_tuple_percent,
  dead_tuple_len as dead_tuple_len_b
from
  pg_class c
  join lateral pgstattuple_approx(c.oid) st on (c.oid not in (select relation from pg_locks where mode = 'AccessExclusiveLock'))  -- skip locked tables,
  join pg_namespace n on n.oid = c.relnamespace
where
  relkind in ('r', 'm')
  and c.relpages >= 128 -- tables > 1mb
  and not n.nspname like any (array[E'pg\\_%', 'information_schema']);
$sql$,
'{"prometheus_all_gauge_columns": true}'
);

/* Stored procedure needed for fetching stat_statements data - needs pg_stat_statements extension enabled on the machine!
 NB! approx_free_percent is just an average. more exact way would be to calculate a weighed average in Go
*/
insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_comment, m_is_helper)
values (
'get_table_bloat_approx',
9.5,
$sql$
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgstattuple;

CREATE OR REPLACE FUNCTION get_table_bloat_approx(
  OUT approx_free_percent double precision, OUT approx_free_space double precision,
  OUT dead_tuple_percent double precision, OUT dead_tuple_len double precision
) AS
$$
    select
      avg(approx_free_percent)::double precision as approx_free_percent,
      sum(approx_free_space)::double precision as approx_free_space,
      avg(dead_tuple_percent)::double precision as dead_tuple_percent,
      sum(dead_tuple_len)::double precision as dead_tuple_len
    from
      pg_class c
      join
      pg_namespace n on n.oid = c.relnamespace
      join lateral pgstattuple_approx(c.oid) on (c.oid not in (select relation from pg_locks where mode = 'AccessExclusiveLock'))  -- skip locked tables
    where
      relkind in ('r', 'm')
      and c.relpages >= 128 -- tables >1mb
      and not n.nspname like any (array[E'pg\\_%', 'information_schema'])
$$ LANGUAGE sql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_table_bloat_approx() TO pgwatch2;
COMMENT ON FUNCTION get_table_bloat_approx() is 'created for pgwatch2';

-- below routine fixes function search_path to only include "more secure" schemas with no "public" CREATE privileges
DO $_$
    DECLARE
        l_secure_schemas_from_search_path text;
    BEGIN
        SELECT string_agg(safe_sp, ', ' ORDER BY rank) INTO l_secure_schemas_from_search_path FROM (
           SELECT quote_ident(nspname) AS safe_sp, rank
           FROM unnest(regexp_split_to_array(current_setting('search_path'), ',')) WITH ORDINALITY AS csp(schema_name, rank)
                    JOIN pg_namespace n
                         ON quote_ident(n.nspname) = CASE WHEN schema_name = '"$user"' THEN quote_ident(user) ELSE trim(schema_name) END
           WHERE NOT has_schema_privilege('public', n.oid, 'CREATE')
        ) x;

        IF coalesce(l_secure_schemas_from_search_path, '') = '' THEN
            RAISE NOTICE 'search_path = %', current_setting('search_path');
            RAISE EXCEPTION $$get_table_bloat_approx() SECURITY DEFINER helper will not be created as all schemas on search_path are unsecured where all users can create objects -
              execute 'REVOKE CREATE ON SCHEMA public FROM PUBLIC' to tighten security or comment out the DO block to disable the check$$;
        ELSE
            RAISE NOTICE '%', format($$ALTER FUNCTION get_table_bloat_approx() SET search_path TO %s$$, l_secure_schemas_from_search_path);
            EXECUTE format($$ALTER FUNCTION get_table_bloat_approx() SET search_path TO %s$$, l_secure_schemas_from_search_path);
        END IF;
    END;
$_$;

COMMIT;
$sql$,
'for internal usage - when connecting user is marked as superuser then the daemon will automatically try to create the needed helpers on the monitored db',
true
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_is_helper)
values (
'get_table_bloat_approx_sql',
9.0,
$sql$
-- small modifications to SQL from https://github.com/ioguix/pgsql-bloat-estimation
-- NB! monitoring user needs SELECT grant on all tables or a SECURITY DEFINER wrapper around that SQL

BEGIN;

CREATE OR REPLACE FUNCTION get_table_bloat_approx_sql(
      OUT full_table_name text,
      OUT approx_bloat_percent double precision,
      OUT approx_bloat_bytes double precision,
      OUT fillfactor integer
    ) RETURNS SETOF RECORD
LANGUAGE sql
SECURITY DEFINER
AS $$

SELECT
  quote_ident(schemaname)||'.'||quote_ident(tblname) as full_table_name,
  bloat_ratio,
  bloat_size,
  fillfactor
FROM (

/* WARNING: executed with a non-superuser role, the query inspect only tables you are granted to read.
* This query is compatible with PostgreSQL 9.0 and more
*/
         SELECT current_database(),
                schemaname,
                tblname,
                bs * tblpages                  AS real_size,
                (tblpages - est_tblpages) * bs AS extra_size,
                CASE
                    WHEN tblpages - est_tblpages > 0
                        THEN 100 * (tblpages - est_tblpages) / tblpages::float
                    ELSE 0
                    END                        AS extra_ratio,
                fillfactor,
                CASE
                    WHEN tblpages - est_tblpages_ff > 0
                        THEN (tblpages - est_tblpages_ff) * bs
                    ELSE 0
                    END                        AS bloat_size,
                CASE
                    WHEN tblpages - est_tblpages_ff > 0
                        THEN 100 * (tblpages - est_tblpages_ff) / tblpages::float
                    ELSE 0
                    END                        AS bloat_ratio,
                is_na
                -- , (pst).free_percent + (pst).dead_tuple_percent AS real_frag
         FROM (
                  SELECT ceil(reltuples / ((bs - page_hdr) / tpl_size)) + ceil(toasttuples / 4)                      AS est_tblpages,
                         ceil(reltuples / ((bs - page_hdr) * fillfactor / (tpl_size * 100))) +
                         ceil(toasttuples / 4)                                                                       AS est_tblpages_ff,
                         tblpages,
                         fillfactor,
                         bs,
                         tblid,
                         schemaname,
                         tblname,
                         heappages,
                         toastpages,
                         is_na
                         -- , stattuple.pgstattuple(tblid) AS pst
                  FROM (
                           SELECT (4 + tpl_hdr_size + tpl_data_size + (2 * ma)
                               - CASE WHEN tpl_hdr_size % ma = 0 THEN ma ELSE tpl_hdr_size % ma END
                               - CASE
                                     WHEN ceil(tpl_data_size)::int % ma = 0 THEN ma
                                     ELSE ceil(tpl_data_size)::int % ma END
                                      )                    AS tpl_size,
                                  bs - page_hdr            AS size_per_block,
                                  (heappages + toastpages) AS tblpages,
                                  heappages,
                                  toastpages,
                                  reltuples,
                                  toasttuples,
                                  bs,
                                  page_hdr,
                                  tblid,
                                  schemaname,
                                  tblname,
                                  fillfactor,
                                  is_na
                           FROM (
                                    SELECT tbl.oid                                                           AS tblid,
                                           ns.nspname                                                        AS schemaname,
                                           tbl.relname                                                       AS tblname,
                                           tbl.reltuples,
                                           tbl.relpages                                                      AS heappages,
                                           coalesce(toast.relpages, 0)                                       AS toastpages,
                                           coalesce(toast.reltuples, 0)                                      AS toasttuples,
                                           coalesce(substring(
                                                            array_to_string(tbl.reloptions, ' ')
                                                            FROM 'fillfactor=([0-9]+)')::smallint,
                                                    100)                                                     AS fillfactor,
                                           current_setting('block_size')::numeric                            AS bs,
                                           CASE
                                               WHEN version() ~ 'mingw32' OR version() ~ '64-bit|x86_64|ppc64|ia64|amd64'
                                                   THEN 8
                                               ELSE 4 END                                                    AS ma,
                                           24                                                                AS page_hdr,
                                           23 + CASE
                                                    WHEN MAX(coalesce(null_frac, 0)) > 0 THEN (7 + count(*)) / 8
                                                    ELSE 0::int END
                                               +
                                           CASE WHEN tbl.relhasoids THEN 4 ELSE 0 END                        AS tpl_hdr_size,
                                           sum((1 - coalesce(s.null_frac, 0)) * coalesce(s.avg_width, 1024)) AS tpl_data_size,
                                           bool_or(att.atttypid = 'pg_catalog.name'::regtype)
                                               OR count(att.attname) <> count(s.attname)                     AS is_na
                                    FROM pg_attribute AS att
                                             JOIN pg_class AS tbl ON att.attrelid = tbl.oid
                                             JOIN pg_namespace AS ns ON ns.oid = tbl.relnamespace
                                             LEFT JOIN pg_stats AS s ON s.schemaname = ns.nspname
                                        AND s.tablename = tbl.relname AND s.inherited = false AND
                                                                        s.attname = att.attname
                                             LEFT JOIN pg_class AS toast ON tbl.reltoastrelid = toast.oid
                                    WHERE att.attnum > 0
                                      AND NOT att.attisdropped
                                      AND tbl.relkind IN ('r', 'm')
                                      AND ns.nspname != 'information_schema'
                                    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, tbl.relhasoids
                                    ORDER BY 2, 3
                                ) AS s
                       ) AS s2
              ) AS s3
         WHERE NOT is_na
 ) s4
$$;

GRANT EXECUTE ON FUNCTION get_table_bloat_approx_sql() TO pgwatch2;
COMMENT ON FUNCTION get_table_bloat_approx_sql() is 'created for pgwatch2';

-- below routine fixes function search_path to only include "more secure" schemas with no "public" CREATE privileges
DO $_$
    DECLARE
        l_secure_schemas_from_search_path text;
    BEGIN
        SELECT string_agg(safe_sp, ', ' ORDER BY rank) INTO l_secure_schemas_from_search_path FROM (
           SELECT quote_ident(nspname) AS safe_sp, rank
           FROM unnest(regexp_split_to_array(current_setting('search_path'), ',')) WITH ORDINALITY AS csp(schema_name, rank)
                    JOIN pg_namespace n
                         ON quote_ident(n.nspname) = CASE WHEN schema_name = '"$user"' THEN quote_ident(user) ELSE trim(schema_name) END
           WHERE NOT has_schema_privilege('public', n.oid, 'CREATE')
        ) x;

        IF coalesce(l_secure_schemas_from_search_path, '') = '' THEN
            RAISE NOTICE 'search_path = %', current_setting('search_path');
            RAISE EXCEPTION $$get_table_bloat_approx_sql() SECURITY DEFINER helper will not be created as all schemas on search_path are unsecured where all users can create objects -
              execute 'REVOKE CREATE ON SCHEMA public FROM PUBLIC' to tighten security or comment out the DO block to disable the check$$;
        ELSE
            RAISE NOTICE '%', format($$ALTER FUNCTION get_table_bloat_approx_sql() SET search_path TO %s$$, l_secure_schemas_from_search_path);
            EXECUTE format($$ALTER FUNCTION get_table_bloat_approx_sql() SET search_path TO %s$$, l_secure_schemas_from_search_path);
        END IF;
    END;
$_$;

COMMIT;
$sql$,
true
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_is_helper)
values (
'get_table_bloat_approx_sql',
12,
$sql$
-- small modifications to SQL from https://github.com/ioguix/pgsql-bloat-estimation
-- NB! monitoring user needs SELECT grant on all tables or a SECURITY DEFINER wrapper around that SQL

BEGIN;

CREATE OR REPLACE FUNCTION get_table_bloat_approx_sql(
      OUT full_table_name text,
      OUT approx_bloat_percent double precision,
      OUT approx_bloat_bytes double precision,
      OUT fillfactor integer
    ) RETURNS SETOF RECORD
LANGUAGE sql
SECURITY DEFINER
AS $$

SELECT
  quote_ident(schemaname)||'.'||quote_ident(tblname) as full_table_name,
  bloat_ratio,
  bloat_size,
  fillfactor
FROM (

/* WARNING: executed with a non-superuser role, the query inspect only tables you are granted to read.
* This query is compatible with PostgreSQL 9.0 and more
*/
         SELECT current_database(),
                schemaname,
                tblname,
                bs * tblpages                  AS real_size,
                (tblpages - est_tblpages) * bs AS extra_size,
                CASE
                    WHEN tblpages - est_tblpages > 0
                        THEN 100 * (tblpages - est_tblpages) / tblpages::float
                    ELSE 0
                    END                        AS extra_ratio,
                fillfactor,
                CASE
                    WHEN tblpages - est_tblpages_ff > 0
                        THEN (tblpages - est_tblpages_ff) * bs
                    ELSE 0
                    END                        AS bloat_size,
                CASE
                    WHEN tblpages - est_tblpages_ff > 0
                        THEN 100 * (tblpages - est_tblpages_ff) / tblpages::float
                    ELSE 0
                    END                        AS bloat_ratio,
                is_na
                -- , (pst).free_percent + (pst).dead_tuple_percent AS real_frag
         FROM (
                  SELECT ceil(reltuples / ((bs - page_hdr) / tpl_size)) + ceil(toasttuples / 4)                      AS est_tblpages,
                         ceil(reltuples / ((bs - page_hdr) * fillfactor / (tpl_size * 100))) +
                         ceil(toasttuples / 4)                                                                       AS est_tblpages_ff,
                         tblpages,
                         fillfactor,
                         bs,
                         tblid,
                         schemaname,
                         tblname,
                         heappages,
                         toastpages,
                         is_na
                         -- , stattuple.pgstattuple(tblid) AS pst
                  FROM (
                           SELECT (4 + tpl_hdr_size + tpl_data_size + (2 * ma)
                               - CASE WHEN tpl_hdr_size % ma = 0 THEN ma ELSE tpl_hdr_size % ma END
                               - CASE
                                     WHEN ceil(tpl_data_size)::int % ma = 0 THEN ma
                                     ELSE ceil(tpl_data_size)::int % ma END
                                      )                    AS tpl_size,
                                  bs - page_hdr            AS size_per_block,
                                  (heappages + toastpages) AS tblpages,
                                  heappages,
                                  toastpages,
                                  reltuples,
                                  toasttuples,
                                  bs,
                                  page_hdr,
                                  tblid,
                                  schemaname,
                                  tblname,
                                  fillfactor,
                                  is_na
                           FROM (
                                    SELECT tbl.oid                                                           AS tblid,
                                           ns.nspname                                                        AS schemaname,
                                           tbl.relname                                                       AS tblname,
                                           tbl.reltuples,
                                           tbl.relpages                                                      AS heappages,
                                           coalesce(toast.relpages, 0)                                       AS toastpages,
                                           coalesce(toast.reltuples, 0)                                      AS toasttuples,
                                           coalesce(substring(
                                                            array_to_string(tbl.reloptions, ' ')
                                                            FROM 'fillfactor=([0-9]+)')::smallint,
                                                    100)                                                     AS fillfactor,
                                           current_setting('block_size')::numeric                            AS bs,
                                           CASE
                                               WHEN version() ~ 'mingw32' OR version() ~ '64-bit|x86_64|ppc64|ia64|amd64'
                                                   THEN 8
                                               ELSE 4 END                                                    AS ma,
                                           24                                                                AS page_hdr,
                                           23 + CASE
                                                    WHEN MAX(coalesce(null_frac, 0)) > 0 THEN (7 + count(*)) / 8
                                                    ELSE 0::int END
                                               +
                                           0                                                                 AS tpl_hdr_size,
                                           sum((1 - coalesce(s.null_frac, 0)) * coalesce(s.avg_width, 1024)) AS tpl_data_size,
                                           bool_or(att.atttypid = 'pg_catalog.name'::regtype)
                                               OR count(att.attname) <> count(s.attname)                     AS is_na
                                    FROM pg_attribute AS att
                                             JOIN pg_class AS tbl ON att.attrelid = tbl.oid
                                             JOIN pg_namespace AS ns ON ns.oid = tbl.relnamespace
                                             LEFT JOIN pg_stats AS s ON s.schemaname = ns.nspname
                                        AND s.tablename = tbl.relname AND s.inherited = false AND
                                                                        s.attname = att.attname
                                             LEFT JOIN pg_class AS toast ON tbl.reltoastrelid = toast.oid
                                    WHERE att.attnum > 0
                                      AND NOT att.attisdropped
                                      AND tbl.relkind IN ('r', 'm')
                                      AND ns.nspname != 'information_schema'
                                    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
                                    ORDER BY 2, 3
                                ) AS s
                       ) AS s2
              ) AS s3
         WHERE NOT is_na
 ) s4
$$;

GRANT EXECUTE ON FUNCTION get_table_bloat_approx_sql() TO pgwatch2;
COMMENT ON FUNCTION get_table_bloat_approx_sql() is 'created for pgwatch2';

-- below routine fixes function search_path to only include "more secure" schemas with no "public" CREATE privileges
DO $_$
    DECLARE
        l_secure_schemas_from_search_path text;
    BEGIN
        SELECT string_agg(safe_sp, ', ' ORDER BY rank) INTO l_secure_schemas_from_search_path FROM (
           SELECT quote_ident(nspname) AS safe_sp, rank
           FROM unnest(regexp_split_to_array(current_setting('search_path'), ',')) WITH ORDINALITY AS csp(schema_name, rank)
                    JOIN pg_namespace n
                         ON quote_ident(n.nspname) = CASE WHEN schema_name = '"$user"' THEN quote_ident(user) ELSE trim(schema_name) END
           WHERE NOT has_schema_privilege('public', n.oid, 'CREATE')
        ) x;

        IF coalesce(l_secure_schemas_from_search_path, '') = '' THEN
            RAISE NOTICE 'search_path = %', current_setting('search_path');
            RAISE EXCEPTION $$get_table_bloat_approx_sql() SECURITY DEFINER helper will not be created as all schemas on search_path are unsecured where all users can create objects -
              execute 'REVOKE CREATE ON SCHEMA public FROM PUBLIC' to tighten security or comment out the DO block to disable the check$$;
        ELSE
            RAISE NOTICE '%', format($$ALTER FUNCTION get_table_bloat_approx_sql() SET search_path TO %s$$, l_secure_schemas_from_search_path);
            EXECUTE format($$ALTER FUNCTION get_table_bloat_approx_sql() SET search_path TO %s$$, l_secure_schemas_from_search_path);
        END IF;
    END;
$_$;

COMMIT;
$sql$,
true
);

/* approx. bloat summary */
insert into pgwatch2.metric(m_name, m_pg_version_from, m_master_only, m_sql, m_column_attrs, m_sql_su)
values (
'table_bloat_approx_summary',
9.5,
true,
$sql$
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  approx_free_percent,
  approx_free_space as approx_free_space_b,
  dead_tuple_percent,
  dead_tuple_len as dead_tuple_len_b
from
  get_table_bloat_approx()
where
  approx_free_space > 0
$sql$,
'{"prometheus_all_gauge_columns": true}',
$sql$
with table_bloat_approx as (
    select
        avg(approx_free_percent)::double precision as approx_free_percent,
        sum(approx_free_space)::double precision as approx_free_space,
        avg(dead_tuple_percent)::double precision as dead_tuple_percent,
        sum(dead_tuple_len)::double precision as dead_tuple_len
    from
        pg_class c
            join
        pg_namespace n on n.oid = c.relnamespace
            join lateral pgstattuple_approx(c.oid) on (c.oid not in (select relation from pg_locks where mode = 'AccessExclusiveLock'))  -- skip locked tables
    where
        relkind in ('r', 'm')
        and c.relpages >= 128 -- tables >1mb
        and not n.nspname like any (array[E'pg\\_%', 'information_schema'])
)
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  approx_free_percent,
  approx_free_space as approx_free_space_b,
  dead_tuple_percent,
  dead_tuple_len as dead_tuple_len_b
from
  table_bloat_approx
where
  approx_free_space > 0;
$sql$
);


insert into pgwatch2.metric(m_name, m_pg_version_from, m_master_only, m_sql, m_column_attrs)
values (
'table_bloat_approx_summary',
10,
true,
$sql$
/* NB! accessing pgstattuple_approx directly requires superuser or pg_stat_scan_tables/pg_monitor builtin roles or
   execute grant on pgstattuple_approx(regclass)
*/
with table_bloat_approx as (
    select
        avg(approx_free_percent)::double precision as approx_free_percent,
        sum(approx_free_space)::double precision as approx_free_space,
        avg(dead_tuple_percent)::double precision as dead_tuple_percent,
        sum(dead_tuple_len)::double precision as dead_tuple_len
    from
        pg_class c
            join
        pg_namespace n on n.oid = c.relnamespace
            join lateral pgstattuple_approx(c.oid) on (c.oid not in (select relation from pg_locks where mode = 'AccessExclusiveLock'))  -- skip locked tables
    where
        relkind in ('r', 'm')
        and c.relpages >= 128 -- tables >1mb
        and not n.nspname != 'information_schema'
)
select
    (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
    approx_free_percent,
    approx_free_space as approx_free_space_b,
    dead_tuple_percent,
    dead_tuple_len as dead_tuple_len_b
from
    table_bloat_approx
where
     approx_free_space > 0;

$sql$,
'{"prometheus_all_gauge_columns": true}'
);

/* approx. bloat summary pure SQL estimate */
insert into pgwatch2.metric(m_name, m_pg_version_from, m_master_only, m_sql, m_column_attrs, m_sql_su)
values (
'table_bloat_approx_summary_sql',
9.0,
true,
$sql$
WITH q_bloat AS (
    select * from get_table_bloat_approx_sql()
)
SELECT
    (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
    (select sum(approx_bloat_bytes) from q_bloat) as approx_table_bloat_b,
    ((select sum(approx_bloat_bytes) from q_bloat) * 100 / pg_database_size(current_database()))::int8 as approx_bloat_percentage
;
$sql$,
'{"prometheus_all_gauge_columns": true}',
$sql$
WITH q_bloat AS (
    SELECT
                quote_ident(schemaname)||'.'||quote_ident(tblname) as full_table_name,
                bloat_ratio as approx_bloat_percent,
                bloat_size as approx_bloat_bytes,
                fillfactor
    FROM (

/* WARNING: executed with a non-superuser role, the query inspect only tables you are granted to read.
* This query is compatible with PostgreSQL 9.0 and more
*/
             SELECT current_database(),
                    schemaname,
                    tblname,
                    bs * tblpages                  AS real_size,
                    (tblpages - est_tblpages) * bs AS extra_size,
                    CASE
                        WHEN tblpages > 0 AND tblpages - est_tblpages > 0
                            THEN 100 * (tblpages - est_tblpages) / tblpages::float
                        ELSE 0
                        END                        AS extra_ratio,
                    fillfactor,
                    CASE
                        WHEN tblpages - est_tblpages_ff > 0
                            THEN (tblpages - est_tblpages_ff) * bs
                        ELSE 0
                        END                        AS bloat_size,
                    CASE
                        WHEN tblpages > 0 AND tblpages - est_tblpages_ff > 0
                            THEN 100 * (tblpages - est_tblpages_ff) / tblpages::float
                        ELSE 0
                        END                        AS bloat_ratio,
                    is_na
                    -- , (pst).free_percent + (pst).dead_tuple_percent AS real_frag
             FROM (
                      SELECT ceil(reltuples / ((bs - page_hdr) / tpl_size)) + ceil(toasttuples / 4)                      AS est_tblpages,
                             ceil(reltuples / ((bs - page_hdr) * fillfactor / (tpl_size * 100))) +
                             ceil(toasttuples / 4)                                                                       AS est_tblpages_ff,
                             tblpages,
                             fillfactor,
                             bs,
                             tblid,
                             schemaname,
                             tblname,
                             heappages,
                             toastpages,
                             is_na
                             -- , stattuple.pgstattuple(tblid) AS pst
                      FROM (
                               SELECT (4 + tpl_hdr_size + tpl_data_size + (2 * ma)
                                   - CASE WHEN tpl_hdr_size % ma = 0 THEN ma ELSE tpl_hdr_size % ma END
                                   - CASE
                                         WHEN ceil(tpl_data_size)::int % ma = 0 THEN ma
                                         ELSE ceil(tpl_data_size)::int % ma END
                                          )                    AS tpl_size,
                                      bs - page_hdr            AS size_per_block,
                                      (heappages + toastpages) AS tblpages,
                                      heappages,
                                      toastpages,
                                      reltuples,
                                      toasttuples,
                                      bs,
                                      page_hdr,
                                      tblid,
                                      schemaname,
                                      tblname,
                                      fillfactor,
                                      is_na
                               FROM (
                                        SELECT tbl.oid                                                           AS tblid,
                                               ns.nspname                                                        AS schemaname,
                                               tbl.relname                                                       AS tblname,
                                               tbl.reltuples,
                                               tbl.relpages                                                      AS heappages,
                                               coalesce(toast.relpages, 0)                                       AS toastpages,
                                               coalesce(toast.reltuples, 0)                                      AS toasttuples,
                                               coalesce(substring(
                                                                array_to_string(tbl.reloptions, ' ')
                                                                FROM 'fillfactor=([0-9]+)')::smallint,
                                                        100)                                                     AS fillfactor,
                                               current_setting('block_size')::numeric                            AS bs,
                                               CASE
                                                   WHEN version() ~ 'mingw32' OR version() ~ '64-bit|x86_64|ppc64|ia64|amd64'
                                                       THEN 8
                                                   ELSE 4 END                                                    AS ma,
                                               24                                                                AS page_hdr,
                                               23 + CASE
                                                        WHEN MAX(coalesce(null_frac, 0)) > 0 THEN (7 + count(*)) / 8
                                                        ELSE 0::int END
                                                   +
                                               CASE WHEN tbl.relhasoids THEN 4 ELSE 0 END                        AS tpl_hdr_size,
                                               sum((1 - coalesce(s.null_frac, 0)) * coalesce(s.avg_width, 1024)) AS tpl_data_size,
                                               bool_or(att.atttypid = 'pg_catalog.name'::regtype)
                                                   OR count(att.attname) <> count(s.attname)                     AS is_na
                                        FROM pg_attribute AS att
                                                 JOIN pg_class AS tbl ON att.attrelid = tbl.oid
                                                 JOIN pg_namespace AS ns ON ns.oid = tbl.relnamespace
                                                 LEFT JOIN pg_stats AS s ON s.schemaname = ns.nspname
                                            AND s.tablename = tbl.relname AND s.inherited = false AND
                                                                            s.attname = att.attname
                                                 LEFT JOIN pg_class AS toast ON tbl.reltoastrelid = toast.oid
                                        WHERE att.attnum > 0
                                          AND NOT att.attisdropped
                                          AND tbl.relkind IN ('r', 'm')
                                          AND ns.nspname != 'information_schema'
                                        GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, tbl.relhasoids
                                        ORDER BY 2, 3
                                    ) AS s
                           ) AS s2
                  ) AS s3
             -- WHERE NOT is_na
         ) s4
)
SELECT /* pgwatch2_generated */
    (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
    (select sum(approx_bloat_bytes) from q_bloat) as approx_table_bloat_b,
    ((select sum(approx_bloat_bytes) from q_bloat) * 100 / pg_database_size(current_database()))::int8 as approx_bloat_percentage;
$sql$
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_master_only, m_sql, m_column_attrs, m_sql_su)
values (
'table_bloat_approx_summary_sql',
12,
true,
$sql$
WITH q_bloat AS (
    select * from get_table_bloat_approx_sql()
)
SELECT
    (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
    (select sum(approx_bloat_bytes) from q_bloat) as approx_table_bloat_b,
    ((select sum(approx_bloat_bytes) from q_bloat) * 100 / pg_database_size(current_database()))::int8 as approx_bloat_percentage
;
$sql$,
'{"prometheus_all_gauge_columns": true}',
$sql$
WITH q_bloat AS (
    SELECT quote_ident(schemaname) || '.' || quote_ident(tblname) as full_table_name,
           bloat_ratio                                            as approx_bloat_percent,
           bloat_size                                             as approx_bloat_bytes,
           fillfactor
    FROM (

/* WARNING: executed with a non-superuser role, the query inspect only tables you are granted to read.
* This query is compatible with PostgreSQL 9.0 and more
*/
             SELECT current_database(),
                    schemaname,
                    tblname,
                    bs * tblpages                  AS real_size,
                    (tblpages - est_tblpages) * bs AS extra_size,
                    CASE
                        WHEN tblpages > 0 AND tblpages - est_tblpages > 0
                            THEN 100 * (tblpages - est_tblpages) / tblpages::float
                        ELSE 0
                        END                        AS extra_ratio,
                    fillfactor,
                    CASE
                        WHEN tblpages - est_tblpages_ff > 0
                            THEN (tblpages - est_tblpages_ff) * bs
                        ELSE 0
                        END                        AS bloat_size,
                    CASE
                        WHEN tblpages > 0 AND tblpages - est_tblpages_ff > 0
                            THEN 100 * (tblpages - est_tblpages_ff) / tblpages::float
                        ELSE 0
                        END                        AS bloat_ratio,
                    is_na
                    -- , (pst).free_percent + (pst).dead_tuple_percent AS real_frag
             FROM (
                      SELECT ceil(reltuples / ((bs - page_hdr) / tpl_size)) + ceil(toasttuples / 4) AS est_tblpages,
                             ceil(reltuples / ((bs - page_hdr) * fillfactor / (tpl_size * 100))) +
                             ceil(toasttuples / 4)                                                  AS est_tblpages_ff,
                             tblpages,
                             fillfactor,
                             bs,
                             tblid,
                             schemaname,
                             tblname,
                             heappages,
                             toastpages,
                             is_na
                             -- , stattuple.pgstattuple(tblid) AS pst
                      FROM (
                               SELECT (4 + tpl_hdr_size + tpl_data_size + (2 * ma)
                                   - CASE WHEN tpl_hdr_size % ma = 0 THEN ma ELSE tpl_hdr_size % ma END
                                   - CASE
                                         WHEN ceil(tpl_data_size)::int % ma = 0 THEN ma
                                         ELSE ceil(tpl_data_size)::int % ma END
                                          )                    AS tpl_size,
                                      bs - page_hdr            AS size_per_block,
                                      (heappages + toastpages) AS tblpages,
                                      heappages,
                                      toastpages,
                                      reltuples,
                                      toasttuples,
                                      bs,
                                      page_hdr,
                                      tblid,
                                      schemaname,
                                      tblname,
                                      fillfactor,
                                      is_na
                               FROM (
                                        SELECT tbl.oid                                                           AS tblid,
                                               ns.nspname                                                        AS schemaname,
                                               tbl.relname                                                       AS tblname,
                                               tbl.reltuples,
                                               tbl.relpages                                                      AS heappages,
                                               coalesce(toast.relpages, 0)                                       AS toastpages,
                                               coalesce(toast.reltuples, 0)                                      AS toasttuples,
                                               coalesce(substring(
                                                                array_to_string(tbl.reloptions, ' ')
                                                                FROM 'fillfactor=([0-9]+)')::smallint,
                                                        100)                                                     AS fillfactor,
                                               current_setting('block_size')::numeric                            AS bs,
                                               CASE
                                                   WHEN version() ~ 'mingw32' OR version() ~ '64-bit|x86_64|ppc64|ia64|amd64'
                                                       THEN 8
                                                   ELSE 4 END                                                    AS ma,
                                               24                                                                AS page_hdr,
                                               23 + CASE
                                                        WHEN MAX(coalesce(null_frac, 0)) > 0 THEN (7 + count(*)) / 8
                                                        ELSE 0::int END
                                                   +
                                               0                                                                 AS tpl_hdr_size,
                                               sum((1 - coalesce(s.null_frac, 0)) * coalesce(s.avg_width, 1024)) AS tpl_data_size,
                                               bool_or(att.atttypid = 'pg_catalog.name'::regtype)
                                                   OR
                                               count(att.attname) <> count(s.attname)                            AS is_na
                                        FROM pg_attribute AS att
                                                 JOIN pg_class AS tbl ON att.attrelid = tbl.oid
                                                 JOIN pg_namespace AS ns ON ns.oid = tbl.relnamespace
                                                 LEFT JOIN pg_stats AS s ON s.schemaname = ns.nspname
                                            AND s.tablename = tbl.relname AND s.inherited = false AND
                                                                            s.attname = att.attname
                                                 LEFT JOIN pg_class AS toast ON tbl.reltoastrelid = toast.oid
                                        WHERE att.attnum > 0
                                          AND NOT att.attisdropped
                                          AND tbl.relkind IN ('r', 'm')
                                          AND ns.nspname != 'information_schema'
                                        GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
                                        ORDER BY 2, 3
                                    ) AS s
                           ) AS s2
                  ) AS s3
             -- WHERE NOT is_na
         ) s4
)
SELECT /* pgwatch2_generated */
    (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
    (select sum(approx_bloat_bytes) from q_bloat) as approx_table_bloat_b,
    ((select sum(approx_bloat_bytes) from q_bloat) * 100 / pg_database_size(current_database()))::int8 as approx_bloat_percentage;
$sql$
);

/* "parent" setting for all of the below "*_hashes" metrics. only this parent "change_events" metric should be used in configs! */
insert into pgwatch2.metric(m_name, m_pg_version_from,m_sql)
values (
'change_events',
9.0,
$sql$
$sql$
);

/* sproc hashes for change detection */
insert into pgwatch2.metric(m_name, m_pg_version_from,m_sql)
values (
'sproc_hashes',
9.0,
$sql$
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  p.oid::text as tag_oid,
  quote_ident(nspname)||'.'||quote_ident(proname) as tag_sproc,
  md5(prosrc)
from
  pg_proc p
  join
  pg_namespace n on n.oid = pronamespace
where
  not nspname like any(array[E'pg\\_%', 'information_schema']);
$sql$
);

/* table (and view) hashes for change detection  */
insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql)
values (
'table_hashes',
9.0,
$sql$
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  quote_ident(table_schema)||'.'||quote_ident(table_name) as tag_table,
  md5((array_agg((c.*)::text order by ordinal_position))::text)
from (
         SELECT current_database()::information_schema.sql_identifier AS table_catalog, nc.nspname::information_schema.sql_identifier AS table_schema, c.relname::information_schema.sql_identifier AS table_name, a.attname::information_schema.sql_identifier AS column_name, a.attnum::information_schema.cardinal_number AS ordinal_position, pg_get_expr(ad.adbin, ad.adrelid)::information_schema.character_data AS column_default,
                CASE
                    WHEN a.attnotnull OR t.typtype = 'd'::"char" AND t.typnotnull THEN 'NO'::text
                    ELSE 'YES'::text
                    END::information_schema.yes_or_no AS is_nullable,
                CASE
                    WHEN t.typtype = 'd'::"char" THEN
                        CASE
                            WHEN bt.typelem <> 0::oid AND bt.typlen = (-1) THEN 'ARRAY'::text
                            WHEN nbt.nspname = 'pg_catalog'::name THEN format_type(t.typbasetype, NULL::integer)
                            ELSE 'USER-DEFINED'::text
                            END
                    ELSE
                        CASE
                            WHEN t.typelem <> 0::oid AND t.typlen = (-1) THEN 'ARRAY'::text
                            WHEN nt.nspname = 'pg_catalog'::name THEN format_type(a.atttypid, NULL::integer)
                            ELSE 'USER-DEFINED'::text
                            END
                    END::information_schema.character_data AS data_type, information_schema._pg_char_max_length(information_schema._pg_truetypid(a.*, t.*), information_schema._pg_truetypmod(a.*, t.*))::information_schema.cardinal_number AS character_maximum_length, information_schema._pg_char_octet_length(information_schema._pg_truetypid(a.*, t.*), information_schema._pg_truetypmod(a.*, t.*))::information_schema.cardinal_number AS character_octet_length, information_schema._pg_numeric_precision(information_schema._pg_truetypid(a.*, t.*), information_schema._pg_truetypmod(a.*, t.*))::information_schema.cardinal_number AS numeric_precision, information_schema._pg_numeric_precision_radix(information_schema._pg_truetypid(a.*, t.*), information_schema._pg_truetypmod(a.*, t.*))::information_schema.cardinal_number AS numeric_precision_radix, information_schema._pg_numeric_scale(information_schema._pg_truetypid(a.*, t.*), information_schema._pg_truetypmod(a.*, t.*))::information_schema.cardinal_number AS numeric_scale, information_schema._pg_datetime_precision(information_schema._pg_truetypid(a.*, t.*), information_schema._pg_truetypmod(a.*, t.*))::information_schema.cardinal_number AS datetime_precision, NULL::character varying::information_schema.character_data AS interval_type, NULL::character varying::information_schema.character_data AS interval_precision, NULL::character varying::information_schema.sql_identifier AS character_set_catalog, NULL::character varying::information_schema.sql_identifier AS character_set_schema, NULL::character varying::information_schema.sql_identifier AS character_set_name, NULL::character varying::information_schema.sql_identifier AS collation_catalog, NULL::character varying::information_schema.sql_identifier AS collation_schema, NULL::character varying::information_schema.sql_identifier AS collation_name,
                CASE
                    WHEN t.typtype = 'd'::"char" THEN current_database()
                    ELSE NULL::name
                    END::information_schema.sql_identifier AS domain_catalog,
                CASE
                    WHEN t.typtype = 'd'::"char" THEN nt.nspname
                    ELSE NULL::name
                    END::information_schema.sql_identifier AS domain_schema,
                CASE
                    WHEN t.typtype = 'd'::"char" THEN t.typname
                    ELSE NULL::name
                    END::information_schema.sql_identifier AS domain_name, current_database()::information_schema.sql_identifier AS udt_catalog, COALESCE(nbt.nspname, nt.nspname)::information_schema.sql_identifier AS udt_schema, COALESCE(bt.typname, t.typname)::information_schema.sql_identifier AS udt_name, NULL::character varying::information_schema.sql_identifier AS scope_catalog, NULL::character varying::information_schema.sql_identifier AS scope_schema, NULL::character varying::information_schema.sql_identifier AS scope_name, NULL::integer::information_schema.cardinal_number AS maximum_cardinality, a.attnum::information_schema.sql_identifier AS dtd_identifier, 'NO'::character varying::information_schema.yes_or_no AS is_self_referencing, 'NO'::character varying::information_schema.yes_or_no AS is_identity, NULL::character varying::information_schema.character_data AS identity_generation, NULL::character varying::information_schema.character_data AS identity_start, NULL::character varying::information_schema.character_data AS identity_increment, NULL::character varying::information_schema.character_data AS identity_maximum, NULL::character varying::information_schema.character_data AS identity_minimum, NULL::character varying::information_schema.yes_or_no AS identity_cycle, 'NEVER'::character varying::information_schema.character_data AS is_generated, NULL::character varying::information_schema.character_data AS generation_expression,
                CASE
                    WHEN c.relkind = 'r'::"char" OR c.relkind = 'v'::"char" AND (EXISTS ( SELECT 1
                                                                                          FROM pg_rewrite
                                                                                          WHERE pg_rewrite.ev_class = c.oid AND pg_rewrite.ev_type = '2'::"char" AND pg_rewrite.is_instead)) AND (EXISTS ( SELECT 1
                                                                                                                                                                                                           FROM pg_rewrite
                                                                                                                                                                                                           WHERE pg_rewrite.ev_class = c.oid AND pg_rewrite.ev_type = '4'::"char" AND pg_rewrite.is_instead)) THEN 'YES'::text
                    ELSE 'NO'::text
                    END::information_schema.yes_or_no AS is_updatable
         FROM pg_attribute a
                  LEFT JOIN pg_attrdef ad ON a.attrelid = ad.adrelid AND a.attnum = ad.adnum, pg_class c, pg_namespace nc, pg_type t
                                                                                                                               JOIN pg_namespace nt ON t.typnamespace = nt.oid
                                                                                                                               LEFT JOIN (pg_type bt
             JOIN pg_namespace nbt ON bt.typnamespace = nbt.oid) ON t.typtype = 'd'::"char" AND t.typbasetype = bt.oid
         WHERE a.attrelid = c.oid AND a.atttypid = t.oid AND nc.oid = c.relnamespace AND NOT pg_is_other_temp_schema(nc.oid) AND a.attnum > 0 AND NOT a.attisdropped AND (c.relkind = ANY (ARRAY['r'::"char", 'v'::"char"])) AND (pg_has_role(c.relowner, 'USAGE'::text) OR has_column_privilege(c.oid, a.attnum, 'SELECT, INSERT, UPDATE, REFERENCES'::text))
) c
where
  not table_schema like any (array[E'pg\\_%', 'information_schema'])
group by
  table_schema, table_name
order by
  table_schema, table_name;
$sql$
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql)
values (
'table_hashes',
9.3,
$sql$
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  quote_ident(table_schema)||'.'||quote_ident(table_name) as tag_table,
  md5((array_agg((c.*)::text order by ordinal_position))::text)
from (
 SELECT current_database()::information_schema.sql_identifier AS table_catalog,
    nc.nspname::information_schema.sql_identifier AS table_schema,
    c.relname::information_schema.sql_identifier AS table_name,
    a.attname::information_schema.sql_identifier AS column_name,
    a.attnum::information_schema.cardinal_number AS ordinal_position,
    pg_get_expr(ad.adbin, ad.adrelid)::information_schema.character_data AS column_default,
        CASE
            WHEN a.attnotnull OR t.typtype = 'd'::"char" AND t.typnotnull THEN 'NO'::text
            ELSE 'YES'::text
        END::information_schema.yes_or_no AS is_nullable,
        CASE
            WHEN t.typtype = 'd'::"char" THEN
            CASE
                WHEN bt.typelem <> 0::oid AND bt.typlen = '-1'::integer THEN 'ARRAY'::text
                WHEN nbt.nspname = 'pg_catalog'::name THEN format_type(t.typbasetype, NULL::integer)
                ELSE 'USER-DEFINED'::text
            END
            ELSE
            CASE
                WHEN t.typelem <> 0::oid AND t.typlen = '-1'::integer THEN 'ARRAY'::text
                WHEN nt.nspname = 'pg_catalog'::name THEN format_type(a.atttypid, NULL::integer)
                ELSE 'USER-DEFINED'::text
            END
        END::information_schema.character_data AS data_type,
    information_schema._pg_char_max_length(information_schema._pg_truetypid(a.*, t.*), information_schema._pg_truetypmod(a.*, t.*))::information_schema.cardinal_number AS character_maximum_length,
    information_schema._pg_char_octet_length(information_schema._pg_truetypid(a.*, t.*), information_schema._pg_truetypmod(a.*, t.*))::information_schema.cardinal_number AS character_octet_length,
    information_schema._pg_numeric_precision(information_schema._pg_truetypid(a.*, t.*), information_schema._pg_truetypmod(a.*, t.*))::information_schema.cardinal_number AS numeric_precision,
    information_schema._pg_numeric_precision_radix(information_schema._pg_truetypid(a.*, t.*), information_schema._pg_truetypmod(a.*, t.*))::information_schema.cardinal_number AS numeric_precision_radix,
    information_schema._pg_numeric_scale(information_schema._pg_truetypid(a.*, t.*), information_schema._pg_truetypmod(a.*, t.*))::information_schema.cardinal_number AS numeric_scale,
    information_schema._pg_datetime_precision(information_schema._pg_truetypid(a.*, t.*), information_schema._pg_truetypmod(a.*, t.*))::information_schema.cardinal_number AS datetime_precision,
    information_schema._pg_interval_type(information_schema._pg_truetypid(a.*, t.*), information_schema._pg_truetypmod(a.*, t.*))::information_schema.character_data AS interval_type,
    NULL::integer::information_schema.cardinal_number AS interval_precision,
    NULL::character varying::information_schema.sql_identifier AS character_set_catalog,
    NULL::character varying::information_schema.sql_identifier AS character_set_schema,
    NULL::character varying::information_schema.sql_identifier AS character_set_name,
        CASE
            WHEN nco.nspname IS NOT NULL THEN current_database()
            ELSE NULL::name
        END::information_schema.sql_identifier AS collation_catalog,
    nco.nspname::information_schema.sql_identifier AS collation_schema,
    co.collname::information_schema.sql_identifier AS collation_name,
        CASE
            WHEN t.typtype = 'd'::"char" THEN current_database()
            ELSE NULL::name
        END::information_schema.sql_identifier AS domain_catalog,
        CASE
            WHEN t.typtype = 'd'::"char" THEN nt.nspname
            ELSE NULL::name
        END::information_schema.sql_identifier AS domain_schema,
        CASE
            WHEN t.typtype = 'd'::"char" THEN t.typname
            ELSE NULL::name
        END::information_schema.sql_identifier AS domain_name,
    current_database()::information_schema.sql_identifier AS udt_catalog,
    COALESCE(nbt.nspname, nt.nspname)::information_schema.sql_identifier AS udt_schema,
    COALESCE(bt.typname, t.typname)::information_schema.sql_identifier AS udt_name,
    NULL::character varying::information_schema.sql_identifier AS scope_catalog,
    NULL::character varying::information_schema.sql_identifier AS scope_schema,
    NULL::character varying::information_schema.sql_identifier AS scope_name,
    NULL::integer::information_schema.cardinal_number AS maximum_cardinality,
    a.attnum::information_schema.sql_identifier AS dtd_identifier,
    'NO'::character varying::information_schema.yes_or_no AS is_self_referencing,
    'NO'::character varying::information_schema.yes_or_no AS is_identity,
    NULL::character varying::information_schema.character_data AS identity_generation,
    NULL::character varying::information_schema.character_data AS identity_start,
    NULL::character varying::information_schema.character_data AS identity_increment,
    NULL::character varying::information_schema.character_data AS identity_maximum,
    NULL::character varying::information_schema.character_data AS identity_minimum,
    NULL::character varying::information_schema.yes_or_no AS identity_cycle,
    'NEVER'::character varying::information_schema.character_data AS is_generated,
    NULL::character varying::information_schema.character_data AS generation_expression,
        CASE
            WHEN c.relkind = 'r'::"char" OR (c.relkind = ANY (ARRAY['v'::"char", 'f'::"char"])) AND pg_column_is_updatable(c.oid::regclass, a.attnum, false) THEN 'YES'::text
            ELSE 'NO'::text
        END::information_schema.yes_or_no AS is_updatable
   FROM pg_attribute a
     LEFT JOIN pg_attrdef ad ON a.attrelid = ad.adrelid AND a.attnum = ad.adnum
     JOIN (pg_class c
     JOIN pg_namespace nc ON c.relnamespace = nc.oid) ON a.attrelid = c.oid
     JOIN (pg_type t
     JOIN pg_namespace nt ON t.typnamespace = nt.oid) ON a.atttypid = t.oid
     LEFT JOIN (pg_type bt
     JOIN pg_namespace nbt ON bt.typnamespace = nbt.oid) ON t.typtype = 'd'::"char" AND t.typbasetype = bt.oid
     LEFT JOIN (pg_collation co
     JOIN pg_namespace nco ON co.collnamespace = nco.oid) ON a.attcollation = co.oid AND (nco.nspname <> 'pg_catalog'::name OR co.collname <> 'default'::name)
  WHERE NOT pg_is_other_temp_schema(nc.oid) AND a.attnum > 0 AND NOT a.attisdropped AND (c.relkind = ANY (ARRAY['r'::"char", 'v'::"char", 'f'::"char"]))

) c
where
  not table_schema like any (array[E'pg\\_%', 'information_schema'])
group by
  table_schema, table_name
order by
  table_schema, table_name;
$sql$
);


/* configuration settings hashes for change detection  */
insert into pgwatch2.metric(m_name, m_pg_version_from,m_sql)
values (
'configuration_hashes',
9.0,
$sql$
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  name as tag_setting,
  coalesce(reset_val, '') as value
from
  pg_settings;
$sql$
);

/* index hashes for change detection  */
insert into pgwatch2.metric(m_name, m_pg_version_from,m_sql)
values (
'index_hashes',
9.0,
$sql$
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  quote_ident(nspname)||'.'||quote_ident(c.relname) as tag_index,
  quote_ident(nspname)||'.'||quote_ident(r.relname) as "table",
  i.indisvalid::text as is_valid,
  coalesce(md5(pg_get_indexdef(i.indexrelid)), random()::text) as md5
from
  pg_index i
  join
  pg_class c on c.oid = i.indexrelid
  join
  pg_class r on r.oid = i.indrelid
  join
  pg_namespace n on n.oid = c.relnamespace
where
  c.relnamespace not in (select oid from pg_namespace where nspname like any(array[E'pg\\_%', 'information_schema']));
$sql$
);

/* object privileges for change detection  */
insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_comment)
values (
'privilege_changes',
9.0,
$sql$
SELECT
    (extract(epoch FROM now()) * 1e9)::int8 AS epoch_ns,
    *
FROM (
    SELECT
        'table'::text AS object_type,
        grantee::text AS tag_role,
        quote_ident(table_schema) || '.' || quote_ident(table_name) AS tag_object,
        privilege_type
    FROM
        information_schema.table_privileges
        /* includes also VIEW-s actually */
    WHERE
        NOT grantee = ANY (
            SELECT
                rolname
            FROM
                pg_roles
            WHERE
                rolsuper
                OR oid < 16384)
            AND NOT table_schema IN ('information_schema', 'pg_catalog')
            /*
             union all

             select
             -- quite a heavy query currently, maybe faster directly via pg_attribute + has_column_privilege?
            'column' AS object_type,
            grantee::text AS tag_role,
            quote_ident(table_schema) || '.' || quote_ident(table_name) AS tag_object,
            privilege_type
        FROM
            information_schema.column_privileges cp
        WHERE
            NOT table_schema IN ('pg_catalog', 'information_schema')
            AND NOT grantee = ANY (
                SELECT
                    rolname
                FROM
                    pg_roles
                WHERE
                    rolsuper
                    OR oid < 16384)
                AND NOT EXISTS (
                    SELECT
                        *
                    FROM
                        information_schema.table_privileges
                    WHERE
                        table_schema = cp.table_schema
                        AND table_name = cp.table_name
                        AND grantee = cp.grantee
                        AND privilege_type = cp.privilege_type) */
                UNION ALL
                SELECT
                    'function' AS object_type,
                    grantee::text AS tag_role,
                    quote_ident(routine_schema) || '.' || quote_ident(routine_name) AS tag_object,
                    privilege_type
                FROM
                    information_schema.routine_privileges
                WHERE
                    NOT routine_schema IN ('information_schema', 'pg_catalog')
                    AND NOT grantee = ANY (
                        SELECT
                            rolname
                        FROM
                            pg_roles
                        WHERE
                            rolsuper
                            OR oid < 16384)
                    UNION ALL
                    SELECT
                        'schema' AS object_type,
                        r.rolname::text AS tag_role,
                        quote_ident(n.nspname) AS tag_object,
                        p.perm AS privilege_type
                    FROM
                        pg_catalog.pg_namespace AS n
                    CROSS JOIN pg_catalog.pg_roles AS r
                    CROSS JOIN (
                        VALUES ('USAGE'),
                            ('CREATE')) AS p (perm)
                    WHERE
                        NOT n.nspname IN ('information_schema', 'pg_catalog')
                            AND n.nspname NOT LIKE 'pg_%'
                            AND NOT r.rolsuper
                            AND r.oid >= 16384
                            AND has_schema_privilege(r.oid, n.oid, p.perm)
                        UNION ALL
                        SELECT
                            'database' AS object_type,
                            r.rolname::text AS role_name,
                            quote_ident(datname) AS tag_object,
                            p.perm AS permission
                        FROM
                            pg_catalog.pg_database AS d
                        CROSS JOIN pg_catalog.pg_roles AS r
                        CROSS JOIN (
                            VALUES ('CREATE'),
                                ('CONNECT'),
                                ('TEMPORARY')) AS p (perm)
                        WHERE
                            d.datname = current_database()
                                AND NOT r.rolsuper
                                AND r.oid >= 16384
                                AND has_database_privilege(r.oid, d.oid, p.perm)
                            UNION ALL
                            SELECT
                                'superusers' AS object_type,
                                rolname::text AS role_name,
                                rolname::text AS tag_object,
                                'SUPERUSER' AS permission
                            FROM
                                pg_catalog.pg_roles
                            WHERE
                                rolsuper
                            UNION ALL
                            SELECT
                                'login_users' AS object_type,
                                rolname::text AS role_name,
                                rolname::text AS tag_object,
                                'LOGIN' AS permission
                            FROM
                                pg_catalog.pg_roles
                            WHERE
                                rolcanlogin) y;

$sql$,
'for internal usage - use "change_detection" metric to enable change tracking'
);

/* Stored procedure needed for CPU load - needs plpythonu! */
insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_comment, m_is_helper)
values (
'get_load_average',
9.1,
$sql$
BEGIN;

CREATE EXTENSION IF NOT EXISTS plpython3u;

CREATE OR REPLACE FUNCTION get_load_average(OUT load_1min float, OUT load_5min float, OUT load_15min float) AS
$$
from os import getloadavg
la = getloadavg()
return [la[0], la[1], la[2]]
$$ LANGUAGE plpython3u VOLATILE;

GRANT EXECUTE ON FUNCTION get_load_average() TO pgwatch2;

COMMENT ON FUNCTION get_load_average() is 'created for pgwatch2';

COMMIT;
$sql$,
'for internal usage - when connecting user is marked as superuser then the daemon will automatically try to create the needed helpers on the monitored db',
true
);

/* for cases where PL/Python is not an option. not included in preset configs */
insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_comment, m_is_helper)
values (
'get_load_average_copy',
9.0,
$sql$
BEGIN;

CREATE UNLOGGED TABLE IF NOT EXISTS get_load_average_copy /* remove the UNLOGGED and IF NOT EXISTS part for < v9.1 */
(
    load_1min  float,
    load_5min  float,
    load_15min float,
    proc_count text,
    last_procid int,
    created_on timestamptz not null default now()
);

CREATE OR REPLACE FUNCTION get_load_average_copy(OUT load_1min float, OUT load_5min float, OUT load_15min float) AS
$$
begin
    if random() < 0.02 then    /* clear the table on ca every 50th call not to be bigger than a couple of pages */
        truncate get_load_average_copy;
    end if;
    copy get_load_average_copy (load_1min, load_5min, load_15min, proc_count, last_procid) from '/proc/loadavg' with (format csv, delimiter ' ');
    select t.load_1min, t.load_5min, t.load_15min into load_1min, load_5min, load_15min from get_load_average_copy t order by created_on desc nulls last limit 1;
    return;
end;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_load_average_copy() TO pgwatch2;

COMMENT ON FUNCTION get_load_average_copy() is 'created for pgwatch2';

-- below routine fixes function search_path to only include "more secure" schemas with no "public" CREATE privileges
DO $_$
    DECLARE
        l_secure_schemas_from_search_path text;
    BEGIN
        SELECT string_agg(safe_sp, ', ' ORDER BY rank) INTO l_secure_schemas_from_search_path FROM (
           SELECT quote_ident(nspname) AS safe_sp, rank
           FROM unnest(regexp_split_to_array(current_setting('search_path'), ',')) WITH ORDINALITY AS csp(schema_name, rank)
                    JOIN pg_namespace n
                         ON quote_ident(n.nspname) = CASE WHEN schema_name = '"$user"' THEN quote_ident(user) ELSE trim(schema_name) END
           WHERE NOT has_schema_privilege('public', n.oid, 'CREATE')
        ) x;

        IF coalesce(l_secure_schemas_from_search_path, '') = '' THEN
            RAISE NOTICE 'search_path = %', current_setting('search_path');
            RAISE EXCEPTION $$get_load_average_copy() SECURITY DEFINER helper will not be created as all schemas on search_path are unsecured where all users can create objects -
              execute 'REVOKE CREATE ON SCHEMA public FROM PUBLIC' to tighten security or comment out the DO block to disable the check$$;
        ELSE
            RAISE NOTICE '%', format($$ALTER FUNCTION get_load_average_copy() SET search_path TO %s$$, l_secure_schemas_from_search_path);
            EXECUTE format($$ALTER FUNCTION get_load_average_copy() SET search_path TO %s$$, l_secure_schemas_from_search_path);
        END IF;
    END;
$_$;

COMMIT;
$sql$,
'for internal usage - when connecting user is marked as superuser then the daemon will automatically try to create the needed helpers on the monitored db',
true
);

/* for cases where PL/Python is not an option. not included in preset configs */
insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_comment, m_is_helper)
values (
'get_load_average_windows',
9.0,
$sql$
/*

 Python function for Windows that is used to extract CPU load from machine via SQL. Since
 os.getloadavg() function is unavailable for Windows, ctypes and kernel32.GetSystemTimes()
 used

*/
--DROP TYPE load_average;
--DROP FUNCTION get_load_average();
--DROP FUNCTION cpu();

BEGIN;

DROP TYPE IF EXISTS load_average CASCADE;

CREATE TYPE load_average AS ( load_1min real, load_5min real, load_15min real );

CREATE OR REPLACE FUNCTION cpu() RETURNS real AS
$$
	from ctypes import windll, Structure, sizeof, byref
	from ctypes.wintypes import DWORD
	import time

	class FILETIME(Structure):
	   _fields_ = [("dwLowDateTime", DWORD), ("dwHighDateTime", DWORD)]

	def GetSystemTimes():
	    __GetSystemTimes = windll.kernel32.GetSystemTimes
	    idleTime, kernelTime, userTime = FILETIME(), FILETIME(), FILETIME()
	    success = __GetSystemTimes(byref(idleTime), byref(kernelTime), byref(userTime))
	    assert success, ctypes.WinError(ctypes.GetLastError())[1]
	    return {
	        "idleTime": idleTime.dwLowDateTime,
	        "kernelTime": kernelTime.dwLowDateTime,
	        "userTime": userTime.dwLowDateTime
	       }

	FirstSystemTimes = GetSystemTimes()
	time.sleep(0.2)
	SecSystemTimes = GetSystemTimes()

	usr = SecSystemTimes['userTime'] - FirstSystemTimes['userTime']
	ker = SecSystemTimes['kernelTime'] - FirstSystemTimes['kernelTime']
	idl = SecSystemTimes['idleTime'] - FirstSystemTimes['idleTime']

	sys = ker + usr
	return min((sys - idl) *100 / sys, 100)
$$ LANGUAGE plpython3u;

CREATE OR REPLACE FUNCTION get_load_average_windows() RETURNS load_average AS
$$
	SELECT val, val, val FROM cpu() AS cpu_now(val);
$$ LANGUAGE sql;

GRANT EXECUTE ON FUNCTION get_load_average_windows() TO pgwatch2;

COMMENT ON FUNCTION get_load_average_windows() is 'created for pgwatch2';

COMMIT;

$sql$,
'for internal usage - when connecting user is marked as superuser then the daemon will automatically try to create the needed helpers on the monitored db',
true
);

/* Stored procedure needed for fetching stat_statements data - needs pg_stat_statements extension enabled on the machine! */
insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_comment, m_is_helper)
values (
'get_stat_statements',
9.2,
$sql$
BEGIN;

CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

CREATE OR REPLACE FUNCTION get_stat_statements() RETURNS TABLE (
	queryid int8, query text, calls int8, total_time float8, rows int8, shared_blks_hit int8, shared_blks_read int8,
	shared_blks_dirtied int8, shared_blks_written int8, local_blks_hit int8, local_blks_read int8, local_blks_dirtied int8,
	local_blks_written int8, temp_blks_read int8, temp_blks_written int8, blk_read_time float8, blk_write_time float8,
  userid int8, dbid int8
) AS
$$
  select
    /* for versions <9.4 we need to spoof the queryid column to make data usable /linkable in Grafana */
    (regexp_replace(md5(s.query), E'\\D', '', 'g'))::varchar(10)::int8 as queryid,
  	s.query, s.calls, s.total_time, s.rows, s.shared_blks_hit, s.shared_blks_read, s.shared_blks_dirtied, s.shared_blks_written,
  	s.local_blks_hit, s.local_blks_read, s.local_blks_dirtied, s.local_blks_written, s.temp_blks_read, s.temp_blks_written,
  	s.blk_read_time, s.blk_write_time, s.userid::int8, s.dbid::int8
  from
    pg_stat_statements s
    join
    pg_database d
      on d.oid = s.dbid and d.datname = current_database()
$$ LANGUAGE sql VOLATILE SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_stat_statements() TO pgwatch2;
COMMENT ON FUNCTION get_stat_statements() IS 'created for pgwatch2';

-- below routine fixes function search_path to only include "more secure" schemas with no "public" CREATE privileges
DO $_$
    DECLARE
        l_secure_schemas_from_search_path text;
    BEGIN
        SELECT string_agg(safe_sp, ', ' ORDER BY rank) INTO l_secure_schemas_from_search_path FROM (
           SELECT quote_ident(nspname) AS safe_sp, rank
           FROM unnest(regexp_split_to_array(current_setting('search_path'), ',')) WITH ORDINALITY AS csp(schema_name, rank)
                    JOIN pg_namespace n
                         ON quote_ident(n.nspname) = CASE WHEN schema_name = '"$user"' THEN quote_ident(user) ELSE trim(schema_name) END
           WHERE NOT has_schema_privilege('public', n.oid, 'CREATE')
        ) x;

        IF coalesce(l_secure_schemas_from_search_path, '') = '' THEN
            RAISE NOTICE 'search_path = %', current_setting('search_path');
            RAISE EXCEPTION $$get_stat_statements() SECURITY DEFINER helper will not be created as all schemas on search_path are unsecured where all users can create objects -
              execute 'REVOKE CREATE ON SCHEMA public FROM PUBLIC' to tighten security or comment out the DO block to disable the check$$;
        ELSE
            RAISE NOTICE '%', format($$ALTER FUNCTION get_stat_statements() SET search_path TO %s$$, l_secure_schemas_from_search_path);
            EXECUTE format($$ALTER FUNCTION get_stat_statements() SET search_path TO %s$$, l_secure_schemas_from_search_path);
        END IF;
    END;
$_$;

COMMIT;
$sql$,
'for internal usage - when connecting user is marked as superuser then the daemon will automatically try to create the needed helpers on the monitored db',
true
);


/* Stored procedure needed for fetching stat_statements data - needs pg_stat_statements extension enabled on the machine! */
insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_comment, m_is_helper)
values (
'get_stat_statements',
9.4,
$sql$
BEGIN;

CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

CREATE OR REPLACE FUNCTION get_stat_statements() RETURNS SETOF pg_stat_statements AS
$$
  select
    s.*
  from
    pg_stat_statements s
    join
    pg_database d
      on d.oid = s.dbid and d.datname = current_database()
$$ LANGUAGE sql VOLATILE SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_stat_statements() TO pgwatch2;
COMMENT ON FUNCTION get_stat_statements() IS 'created for pgwatch2';

-- below routine fixes function search_path to only include "more secure" schemas with no "public" CREATE privileges
DO $_$
    DECLARE
        l_secure_schemas_from_search_path text;
    BEGIN
        SELECT string_agg(safe_sp, ', ' ORDER BY rank) INTO l_secure_schemas_from_search_path FROM (
           SELECT quote_ident(nspname) AS safe_sp, rank
           FROM unnest(regexp_split_to_array(current_setting('search_path'), ',')) WITH ORDINALITY AS csp(schema_name, rank)
                    JOIN pg_namespace n
                         ON quote_ident(n.nspname) = CASE WHEN schema_name = '"$user"' THEN quote_ident(user) ELSE trim(schema_name) END
           WHERE NOT has_schema_privilege('public', n.oid, 'CREATE')
        ) x;

        IF coalesce(l_secure_schemas_from_search_path, '') = '' THEN
            RAISE NOTICE 'search_path = %', current_setting('search_path');
            RAISE EXCEPTION $$get_stat_statements() SECURITY DEFINER helper will not be created as all schemas on search_path are unsecured where all users can create objects -
              execute 'REVOKE CREATE ON SCHEMA public FROM PUBLIC' to tighten security or comment out the DO block to disable the check$$;
        ELSE
            RAISE NOTICE '%', format($$ALTER FUNCTION get_stat_statements() SET search_path TO %s$$, l_secure_schemas_from_search_path);
            EXECUTE format($$ALTER FUNCTION get_stat_statements() SET search_path TO %s$$, l_secure_schemas_from_search_path);
        END IF;
    END;
$_$;

COMMIT;
$sql$,
'for internal usage - when connecting user is marked as superuser then the daemon will automatically try to create the needed helpers on the monitored db',
true
);

/* pgbouncer_stats - assumes also that monitored DB has type 'pgbouncer' */
insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_comment, m_is_helper)
values (
'pgbouncer_stats',
0,
'show stats',
'pgbouncer per db statistics',
false
);

/* pgpool_stats - assumes also that monitored DB has type 'pgpool' */
insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_comment, m_is_helper)
values (
'pgpool_stats',
3.0,
$$
/* SHOW POOL_NODES expected to be 1st "command" */
SHOW POOL_NODES;
/* special handling in code - when below SHOW POOL_PROCESSES line is defined pgpool_stats will have additional summary columns:
 processes_total, processes_active */
SHOW POOL_PROCESSES;
$$,
'pgpool node and process information',
false
);

/* Stored procedure needed for fetching backend/session data */
insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_comment, m_is_helper)
values (
'get_stat_activity',
9.0,
$sql$

DO $OUTER$
DECLARE
  l_pgver double precision;
  l_sproc_text_pre92 text := $SQL$
CREATE OR REPLACE FUNCTION get_stat_activity() RETURNS SETOF pg_stat_activity AS
$$
  select * from pg_stat_activity where datname = current_database() and procpid != pg_backend_pid()
$$ LANGUAGE sql VOLATILE SECURITY DEFINER;
$SQL$;
  l_sproc_text_92_plus text := $SQL$
CREATE OR REPLACE FUNCTION get_stat_activity() RETURNS SETOF pg_stat_activity AS
$$
  select * from pg_stat_activity where datname = current_database() and pid != pg_backend_pid()
$$ LANGUAGE sql VOLATILE SECURITY DEFINER;
$SQL$;
BEGIN
  SELECT ((regexp_matches(
      regexp_replace(current_setting('server_version'), '(beta|devel).*', '', 'g'),
        E'\\d+\\.?\\d+?'))[1])::double precision INTO l_pgver;
  EXECUTE format(CASE WHEN l_pgver > 9.1 THEN l_sproc_text_92_plus ELSE l_sproc_text_pre92 END);
END;
$OUTER$;

GRANT EXECUTE ON FUNCTION get_stat_activity() TO pgwatch2;
COMMENT ON FUNCTION get_stat_activity() IS 'created for pgwatch2';

$sql$,
'for internal usage - when connecting user is marked as superuser then the daemon will automatically try to create the needed helpers on the monitored db',
true
);

/* replication slot info */

insert into pgwatch2.metric(m_name, m_pg_version_from, m_master_only, m_sql, m_column_attrs)
values (
'replication_slots',
9.4,
true,
$sql$
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  slot_name::text as tag_slot_name,
  coalesce(plugin, 'physical')::text as tag_plugin,
  active,
  case when active then 0 else 1 end as non_active_int,
  pg_xlog_location_diff(pg_current_xlog_location(), restart_lsn)::int8 as restart_lsn_lag_b,
  greatest(age(xmin), age(catalog_xmin))::int8 as xmin_age_tx
from
  pg_replication_slots;
$sql$,
'{"prometheus_all_gauge_columns": true}'
);


insert into pgwatch2.metric(m_name, m_pg_version_from, m_master_only, m_sql, m_column_attrs)
values (
'replication_slots',
10,
true,
$sql$
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  slot_name::text as tag_slot_name,
  coalesce(plugin, 'physical')::text as plugin,
  active,
  case when active then 0 else 1 end as non_active_int,
  pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)::int8 as restart_lsn_lag_b,
  pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn)::int8 as confirmed_flush_lsn_lag_b,
  greatest(age(xmin), age(catalog_xmin))::int8 as xmin_age_tx
from
  pg_replication_slots;
$sql$,
'{"prometheus_all_gauge_columns": true}'
);


insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs)
values (
'psutil_cpu',
9.1,
$sql$

SELECT
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  round(cpu_utilization::numeric, 2)::float as cpu_utilization,
  round(load_1m_norm::numeric, 2)::float as load_1m_norm,
  round(load_1m::numeric, 2)::float as load_1m,
  round(load_5m_norm::numeric, 2)::float as load_5m_norm,
  round(load_5m::numeric, 2)::float as load_5m,
  round("user"::numeric, 2)::float as "user",
  round(system::numeric, 2)::float as system,
  round(idle::numeric, 2)::float as idle,
  round(iowait::numeric, 2)::float as iowait,
  round(irqs::numeric, 2)::float as irqs,
  round(other::numeric, 2)::float as other
from
  get_psutil_cpu();
$sql$,
'{"prometheus_all_gauge_columns": true}'
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs, m_is_helper)
values (
'get_psutil_cpu',
9.1,
$sql$
/*  Pre-requisites: PL/Pythonu and "psutil" Python package (e.g. pip install psutil)
    NB! "psutil" is known to behave differently depending on the used version and operating system, so if getting
    errors please adjust to your needs. "psutil" documentation here: https://psutil.readthedocs.io/en/latest/
*/
CREATE EXTENSION IF NOT EXISTS plpython3u; /* NB! "plpython3u" might need changing to "plpythonu" (Python 2) everywhere for older OS-es */

CREATE OR REPLACE FUNCTION get_psutil_cpu(
	OUT cpu_utilization float8, OUT load_1m_norm float8, OUT load_1m float8, OUT load_5m_norm float8, OUT load_5m float8,
    OUT "user" float8, OUT system float8, OUT idle float8, OUT iowait float8, OUT irqs float8, OUT other float8
)
 LANGUAGE plpython3u
AS $FUNCTION$

from os import getloadavg
from psutil import cpu_times_percent, cpu_percent, cpu_count
from threading import Thread

class GetCpuPercentThread(Thread):
    def __init__(self, interval_seconds):
        self.interval_seconds = interval_seconds
        self.cpu_utilization_info = None
        super(GetCpuPercentThread, self).__init__()

    def run(self):
        self.cpu_utilization_info = cpu_percent(self.interval_seconds)

t = GetCpuPercentThread(0.5)
t.start()

ct = cpu_times_percent(0.5)
la = getloadavg()

t.join()

return t.cpu_utilization_info, la[0] / cpu_count(), la[0], la[1] / cpu_count(), la[1], ct.user, ct.system, ct.idle, ct.iowait, ct.irq + ct.softirq, ct.steal + ct.guest + ct.guest_nice

$FUNCTION$;

GRANT EXECUTE ON FUNCTION get_psutil_cpu() TO pgwatch2;
COMMENT ON FUNCTION get_psutil_cpu() IS 'created for pgwatch2';


$sql$,
'{"prometheus_all_gauge_columns": true}',
true
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs)
values (
'psutil_mem',
9.1,
$sql$
SELECT
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  total, used, free, buff_cache, available, percent,
  swap_total, swap_used, swap_free, swap_percent
from
  get_psutil_mem();
$sql$,
'{"prometheus_all_gauge_columns": true}'
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs, m_is_helper)
values (
'get_psutil_mem',
9.1,
$sql$
/* Pre-requisites: PL/Pythonu and "psutil" Python package (e.g. pip install psutil) */
CREATE EXTENSION IF NOT EXISTS plpython3u; -- NB! "plpython3u" might need changing to "plpythonu" (Python 2) everywhere for older OS-es

CREATE OR REPLACE FUNCTION get_psutil_mem(
	OUT total float8, OUT used float8, OUT free float8, OUT buff_cache float8, OUT available float8, OUT percent float8,
	OUT swap_total float8, OUT swap_used float8, OUT swap_free float8, OUT swap_percent float8
)
 LANGUAGE plpython3u
AS $FUNCTION$
from psutil import virtual_memory, swap_memory
vm = virtual_memory()
sw = swap_memory()
return vm.total, vm.used, vm.free, vm.buffers + vm.cached, vm.available, vm.percent, sw.total, sw.used, sw.free, sw.percent
$FUNCTION$;

GRANT EXECUTE ON FUNCTION get_psutil_mem() TO pgwatch2;
COMMENT ON FUNCTION get_psutil_mem() IS 'created for pgwatch2';

$sql$,
'{"prometheus_all_gauge_columns": true}',
true
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs)
values (
'psutil_disk',
9.1,
$sql$
SELECT
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  dir_or_tablespace as tag_dir_or_tablespace,
  path as tag_path,
  total, used, free, percent
from
  get_psutil_disk();
$sql$,
'{"prometheus_all_gauge_columns": true}'
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs, m_is_helper)
values (
'get_psutil_disk',
9.1,
$sql$
/* Pre-requisites: PL/Pythonu and "psutil" Python package (e.g. pip install psutil) */
CREATE EXTENSION IF NOT EXISTS plpython3u; /* NB! "plpython3u" might need changing to "plpythonu" (Python 2) everywhere for older OS-es */

CREATE OR REPLACE FUNCTION get_psutil_disk(
	OUT dir_or_tablespace text, OUT path text, OUT total float8, OUT used float8, OUT free float8, OUT percent float8
)
 RETURNS SETOF record
 LANGUAGE plpython3u
 SECURITY DEFINER
AS $FUNCTION$

from os import stat
from os.path import join, exists
from psutil import disk_usage
ret_list = []

# data_directory
r = plpy.execute("select current_setting('data_directory') as dd, current_setting('log_directory') as ld, current_setting('server_version_num')::int as pgver")
dd = r[0]['dd']
ld = r[0]['ld']
du_dd = disk_usage(dd)
ret_list.append(['data_directory', dd, du_dd.total, du_dd.used, du_dd.free, du_dd.percent])

dd_stat = stat(dd)
# log_directory
if ld:
    if not ld.startswith('/'):
        ld_path = join(dd, ld)
    else:
        ld_path = ld
    if exists(ld_path):
        log_stat = stat(ld_path)
        if log_stat.st_dev == dd_stat.st_dev:
            pass                                # no new info, same device
        else:
            du = disk_usage(ld_path)
            ret_list.append(['log_directory', ld_path, du.total, du.used, du.free, du.percent])

# WAL / XLOG directory
# plpy.notice('pg_wal' if r[0]['pgver'] >= 100000 else 'pg_xlog', r[0]['pgver'])
joined_path_wal = join(r[0]['dd'], 'pg_wal' if r[0]['pgver'] >= 100000 else 'pg_xlog')
wal_stat = stat(joined_path_wal)
if wal_stat.st_dev == dd_stat.st_dev:
    pass                                # no new info, same device
else:
    du = disk_usage(joined_path_wal)
    ret_list.append(['pg_wal', joined_path_wal, du.total, du.used, du.free, du.percent])

# add user created tablespaces if any
sql_tablespaces = """
    select spcname as name, pg_catalog.pg_tablespace_location(oid) as location
    from pg_catalog.pg_tablespace where not spcname like any(array[E'pg\\_%'])"""
for row in plpy.cursor(sql_tablespaces):
    du = disk_usage(row['location'])
    ret_list.append([row['name'], row['location'], du.total, du.used, du.free, du.percent])
return ret_list

$FUNCTION$;

GRANT EXECUTE ON FUNCTION get_psutil_disk() TO pgwatch2;
COMMENT ON FUNCTION get_psutil_disk() IS 'created for pgwatch2';

$sql$,
'{"prometheus_all_gauge_columns": true}',
true
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs)
values (
'psutil_disk_io_total',
9.1,
$sql$
SELECT
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  read_count,
  write_count,
  read_bytes,
  write_bytes
from
  get_psutil_disk_io_total();
$sql$,
'{"prometheus_all_gauge_columns": true}'
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs, m_is_helper)
values (
'get_psutil_disk_io_total',
9.1,
$sql$

/* Pre-requisites: PL/Pythonu and "psutil" Python package (e.g. pip install psutil) */
CREATE EXTENSION IF NOT EXISTS plpython3u; /* NB! "plpython3u" might need changing to "plpythonu" (Python 2) everywhere for older OS-es */

CREATE OR REPLACE FUNCTION get_psutil_disk_io_total(
	OUT read_count float8, OUT write_count float8, OUT read_bytes float8, OUT write_bytes float8
)
 LANGUAGE plpython3u
AS $FUNCTION$
from psutil import disk_io_counters
dc = disk_io_counters(perdisk=False)
if dc:
    return dc.read_count, dc.write_count, dc.read_bytes, dc.write_bytes
else:
    return None, None, None, None
$FUNCTION$;

GRANT EXECUTE ON FUNCTION get_psutil_disk_io_total() TO pgwatch2;
COMMENT ON FUNCTION get_psutil_disk_io_total() IS 'created for pgwatch2';

$sql$,
'{"prometheus_all_gauge_columns": true}',
true
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs)
values (
'archiver',
9.4,
$sql$
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  archived_count,
  failed_count,
  case when coalesce(last_failed_time, '1970-01-01'::timestamptz) > coalesce(last_archived_time, '1970-01-01'::timestamptz) then 1 else 0 end as is_failing_int,
  extract(epoch from now() - last_failed_time)::int8 as seconds_since_last_failure
from
  pg_stat_archiver
where
  current_setting('archive_mode') in ('on', 'always');
$sql$,
'{"prometheus_gauge_columns": ["is_failing_int", "seconds_since_last_failure"]}'
);

/* Stored procedure for getting WAL folder size */
insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_comment, m_is_helper)
values (
'get_wal_size',
9.0,
$sql$

CREATE OR REPLACE FUNCTION get_wal_size() RETURNS int8 AS
$$
select sum((pg_stat_file('pg_xlog/'||f)).size)::int8 from (select pg_ls_dir('pg_xlog') f) ls
$$ LANGUAGE sql VOLATILE SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_wal_size() TO pgwatch2;
COMMENT ON FUNCTION get_wal_size() IS 'created for pgwatch2';

$sql$,
'for internal usage - when connecting user is marked as superuser then the daemon will automatically try to create the needed helpers on the monitored db',
true
);

/* Stored procedure for getting WAL folder size */
insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_comment, m_is_helper)
values (
'get_wal_size',
10,
$sql$

CREATE OR REPLACE FUNCTION get_wal_size() RETURNS int8 AS
$$
select (sum((pg_stat_file('pg_wal/' || name)).size))::int8 from pg_ls_waldir()
$$ LANGUAGE sql VOLATILE SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_wal_size() TO pgwatch2;
COMMENT ON FUNCTION get_wal_size() IS 'created for pgwatch2';

$sql$,
'for internal usage - when connecting user is marked as superuser then the daemon will automatically try to create the needed helpers on the monitored db',
true
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_sql_su)
values (
'wal_size',
9.0,
$sql$
select
    (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
    get_wal_size() as wal_size_b;
$sql$,
$sql$
select
    (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
    sum((pg_stat_file('pg_xlog/'||f)).size)::int8 as wal_size_b from (select pg_ls_dir('pg_xlog') f) ls;
$sql$
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs, m_sql_su)
values (
'wal_size',
10,
$sql$
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  get_wal_size() as wal_size_b;
$sql$,
'{"prometheus_all_gauge_columns": true}',
$sql$
/* NB! If using not a real superuser but a role with "pg_monitor" grant then below execute grant is needed:
  GRANT EXECUTE ON FUNCTION pg_stat_file(text) to pgwatch2;
*/
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
   (sum((pg_stat_file('pg_wal/' || name)).size))::int8 as wal_size_b
from pg_ls_waldir();
$sql$
);


insert into pgwatch2.metric(m_name, m_pg_version_from, m_standby_only, m_sql, m_column_attrs)
values (
'wal_receiver',
9.2,
true,
$sql$
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  pg_xlog_location_diff(pg_last_xlog_receive_location(), pg_last_xlog_replay_location())::int8 as replay_lag_b,
  extract(epoch from (now() - pg_last_xact_replay_timestamp()))::int8 as last_replay_s;
$sql$,
'{"prometheus_all_gauge_columns": true}'
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_standby_only, m_sql, m_column_attrs)
values (
'wal_receiver',
10,
true,
$sql$
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  pg_wal_lsn_diff(pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn())::int8 as replay_lag_b,
  extract(epoch from (now() - pg_last_xact_replay_timestamp()))::int8 as last_replay_s;
$sql$,
'{"prometheus_all_gauge_columns": true}'
);


/* from PG10+ it's best to use the "pg_monitor" system role to grant access to this and other pg_stat* views */
insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_comment, m_is_helper)
values (
'get_stat_replication',
9.2,
$sql$

CREATE OR REPLACE FUNCTION get_stat_replication() RETURNS SETOF pg_stat_replication AS
$$
  select * from pg_stat_replication
$$ LANGUAGE sql VOLATILE SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_stat_replication() TO pgwatch2;
COMMENT ON FUNCTION get_stat_replication() IS 'created for pgwatch2';

$sql$,
'for internal usage - when connecting user is marked as superuser then the daemon will automatically try to create the needed helpers on the monitored db',
true
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs)
values (
'settings',
9.0,
$sql$
with qs as (
  select name, setting from pg_settings
)
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  current_setting('server_version') as server_version,
  current_setting('server_version_num')::int8 as server_version_num,
  current_setting('block_size')::int as block_size,
  current_setting('max_connections')::int as max_connections,
  current_setting('hot_standby') as hot_standby,
  (select setting from qs where name = 'hot_standby_feedback') as hot_standby_feedback,
  current_setting('fsync') as fsync,
  current_setting('full_page_writes') as full_page_writes,
  current_setting('synchronous_commit') as synchronous_commit,
  (select setting from qs where name = 'wal_compression') as wal_compression,
  (select setting from qs where name = 'wal_log_hints') as wal_log_hints,
  (select setting from qs where name = 'synchronous_standby_names') as synchronous_standby_names,
  current_setting('shared_buffers') as shared_buffers,
  current_setting('work_mem') as work_mem,
  current_setting('maintenance_work_mem') as maintenance_work_mem,
  current_setting('effective_cache_size') as effective_cache_size,
  (select setting::int8 from qs where name = 'default_statistics_target') as default_statistics_target,
  (select setting::float8 from qs where name = 'random_page_cost') as random_page_cost,
  pg_size_pretty(((select setting::int8 from qs where name = 'min_wal_size') * 1024^2)::int8) as min_wal_size,
  pg_size_pretty(((select setting::int8 from qs where name = 'max_wal_size') * 1024^2)::int8) as max_wal_size,
  (select setting from qs where name = 'checkpoint_segments') as checkpoint_segments,
  current_setting('checkpoint_timeout') as checkpoint_timeout,
  current_setting('checkpoint_completion_target') as checkpoint_completion_target,
  (select setting::int8 from qs where name = 'max_worker_processes') as max_worker_processes,
  (select setting::int8 from qs where name = 'max_parallel_workers') as max_parallel_workers,
  (select setting::int8 from qs where name = 'max_parallel_workers_per_gather') as max_parallel_workers_per_gather,
  (select case when setting = 'on' then 1 else 0 end from qs where name = 'jit') as jit,
  (select case when setting = 'on' then 1 else 0 end from qs where name = 'ssl') as ssl,
  current_setting('statement_timeout') as statement_timeout,
  current_setting('deadlock_timeout') as deadlock_timeout,
  (select setting from qs where name = 'data_checksums') as data_checksums,
  (select setting::int8 from qs where name = 'max_connections') as max_connections,
  (select setting::int8 from qs where name = 'max_wal_senders') as max_wal_senders,
  (select setting::int8 from qs where name = 'max_replication_slots') as max_replication_slots,
  (select setting::int8 from qs where name = 'max_prepared_transactions') as max_prepared_transactions,
  (select setting::int8 from qs where name = 'lock_timeout') || ' (ms)' as lock_timeout,
  (select setting from qs where name = 'archive_mode') as archive_mode,
  (select setting from qs where name = 'archive_command') as archive_command,
  current_setting('archive_timeout') as archive_timeout,
  (select setting from qs where name = 'shared_preload_libraries') as shared_preload_libraries,
  (select setting from qs where name = 'listen_addresses') as listen_addresses,
  (select setting from qs where name = 'ssl') as ssl,
  (select setting from qs where name = 'autovacuum') as autovacuum,
  (select setting::int8 from qs where name = 'autovacuum_max_workers') as autovacuum_max_workers,
  (select setting::float8 from qs where name = 'autovacuum_vacuum_scale_factor') as autovacuum_vacuum_scale_factor,
  (select setting::float8 from qs where name = 'autovacuum_vacuum_threshold') as autovacuum_vacuum_threshold,
  (select setting::float8 from qs where name = 'autovacuum_analyze_scale_factor') as autovacuum_analyze_scale_factor,
  (select setting::float8 from qs where name = 'autovacuum_analyze_threshold') as autovacuum_analyze_scale_factor
;
$sql$,
'{"prometheus_all_gauge_columns": true}'
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs)
values (
'stat_activity_realtime',
9.0,
$sql$
SELECT
    (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
    pid as tag_pid,
    usename::text AS user,
    application_name AS appname,
    coalesce(client_addr::text, 'local') AS ip,
    extract(epoch FROM (now() - query_start))::int AS duration_s,
    waiting::int,
    case when sa.waiting then
             (select array_to_string((select array_agg(distinct b.pid order by b.pid) from pg_locks b join pg_locks l on l.database = b.database and l.relation = b.relation
                                      where l.pid = sa.procpid and b.pid != l.pid and b.granted and not l.granted), ','))
         else
             null
        end as blocking_pids,
    ltrim(regexp_replace(current_query, E'[ \\t\\n\\r]+' , ' ', 'g'))::varchar(300) AS query
FROM
    pg_stat_activity sa
WHERE
    current_query <> '<IDLE>'
    AND procpid != pg_backend_pid()
    AND datname = current_database()
    AND NOW() - query_start > '500ms'::interval
ORDER BY
    NOW() - query_start DESC
LIMIT 25;
$sql$,
'{"prometheus_all_gauge_columns": true}'
);
insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs)
values (
'stat_activity_realtime',
9.2,
$sql$
SELECT
    (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
    pid as tag_pid,
    usename::text AS user,
    application_name AS appname,
    coalesce(client_addr::text, 'local') AS ip,
    extract(epoch FROM (now() - query_start))::int AS duration_s,
    waiting::int,
    case when sa.waiting then
        (select array_to_string((select array_agg(distinct b.pid order by b.pid) from pg_locks b join pg_locks l on l.database = b.database and l.relation = b.relation
           where l.pid = sa.pid and b.pid != l.pid and b.granted and not l.granted), ','))
        else
            null
    end as blocking_pids,
    ltrim(regexp_replace(query, E'[ \\t\\n\\r]+' , ' ', 'g'))::varchar(300) AS query
FROM
    pg_stat_activity sa
WHERE
    state != 'idle'
    AND pid != pg_backend_pid()
    AND datname = current_database()
    AND now() - query_start > '500ms'::interval
ORDER BY
    now() - query_start DESC
LIMIT 25;
$sql$,
'{"prometheus_all_gauge_columns": true}'
);
insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs)
values (
'stat_activity_realtime',
9.6,
$sql$
SELECT
    (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
    pid as tag_pid,
    usename::text AS user,
    application_name AS appname,
    coalesce(client_addr::text, 'local') AS ip,
    extract(epoch FROM (now() - query_start))::int AS duration_s,
    (wait_event_type IS NOT NULL)::int AS waiting,
    array_to_string(pg_blocking_pids(pid), ',') as blocking_pids,
    ltrim(regexp_replace(query, E'[ \\t\\n\\r]+' , ' ', 'g'))::varchar(300) AS query
FROM
    pg_stat_activity
WHERE
  state != 'idle'
  AND pid != pg_backend_pid()
  AND datname = current_database()
  AND now() - query_start > '500ms'::interval
ORDER BY
  now() - query_start DESC
LIMIT 25;
$sql$,
'{"prometheus_all_gauge_columns": true}'
);
insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs)
values (
'stat_activity_realtime',
10,
$sql$
SELECT
    (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
    pid as tag_pid,
    usename::text AS user,
    application_name AS appname,
    coalesce(client_addr::text, 'local') AS ip,
    extract(epoch FROM (now() - query_start))::int AS duration_s,
    (coalesce(wait_event_type, '') IN ('LWLockNamed', 'Lock', 'BufferPin'))::int AS waiting,
    array_to_string(pg_blocking_pids(pid), ',') as blocking_pids,
    ltrim(regexp_replace(query, E'[ \\t\\n\\r]+' , ' ', 'g'))::varchar(300) AS query
FROM
    pg_stat_activity
WHERE
  state != 'idle'
  AND backend_type IN ('client backend', 'autovacuum worker')
  AND pid != pg_backend_pid()
  AND datname = current_database()
  AND now() - query_start > '500ms'::interval
ORDER BY
  now() - query_start DESC
LIMIT 25;
$sql$,
'{"prometheus_all_gauge_columns": true}'
);

/* RECO */

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql)
values (
'recommendations',
9.0,
'/* dummy placeholder - special handling in code to collect other metrics named reco_* */'
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs, m_master_only)
values (
'reco_add_index',
9.1,
$sql$
/* assumes the pg_qualstats extension and superuser or select grants on pg_qualstats_indexes_ddl view */
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  'create_index'::text as tag_reco_topic,
  quote_ident(nspname::text)||'.'||quote_ident(relid::text) as tag_object_name,
  ddl as recommendation,
  ('qual execution count: '|| execution_count)::text as extra_info
from
  pg_qualstats_indexes_ddl
order by
  execution_count desc
limit 25;
$sql$,
'{"prometheus_all_gauge_columns": true}',
true
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs, m_master_only)
values (
'reco_add_index_ext_qualstats_2.0',
9.1,
$sql$
  /* assumes the pg_qualstats extension and superuser or select grant on pg_qualstats_index_advisor() function */
SELECT
  epoch_ns,
  tag_reco_topic,
  tag_object_name,
  recommendation,
  case when exists (select * from pg_inherits
                    where inhrelid = regclass(tag_object_name)
                    ) then 'NB! Partitioned table, create the index on parent' else extra_info
  end as extra_info
FROM (
         SELECT (extract(epoch from now()) * 1e9)::int8    as epoch_ns,
                'create_index'::text                       as tag_reco_topic,
                (regexp_matches(v::text, E'ON (.*?) '))[1] as tag_object_name,
                v::text                                    as recommendation,
                ''                                         as extra_info
         FROM json_array_elements(
                      pg_qualstats_index_advisor() -> 'indexes') v
     ) x
ORDER BY tag_object_name
LIMIT 25;
$sql$,
'{"prometheus_all_gauge_columns": true}',
true
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs, m_master_only)
values (
'reco_default_public_schema',
9.1,
$sql$
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  'default_public_schema_privs'::text as tag_reco_topic,
  nspname::text as tag_object_name,
  'REVOKE CREATE ON SCHEMA public FROM PUBLIC;'::text as recommendation,
  'only authorized users should be allowed to create new objects'::text as extra_info
from
  pg_namespace
where
  nspname = 'public'
  and nspacl::text ~ E'[,\\{]+=U?C/'
;
$sql$,
'{"prometheus_all_gauge_columns": true}',
true
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs, m_master_only)
values (
'reco_drop_index',
9.0,
$sql$
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  'drop_index'::text as tag_reco_topic,
  quote_ident(schemaname)||'.'||quote_ident(indexrelname) as tag_object_name,
  ('DROP INDEX ' || quote_ident(schemaname)||'.'||quote_ident(indexrelname) || ';')::text as recommendation,
  'NB! Before dropping make sure to also check replica pg_stat_user_indexes.idx_scan count if using them for queries'::text as extra_info
from
  pg_stat_user_indexes
  join
  pg_index using (indexrelid)
where
  idx_scan = 0
  and ((pg_relation_size(indexrelid)::numeric / (pg_database_size(current_database()))) > 0.005 /* 0.5% DB size threshold */
    or indisvalid)
  and not indisprimary
;
$sql$,
'{"prometheus_all_gauge_columns": true}',
true
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs, m_master_only)
values (
'reco_drop_index',
9.4,
$sql$
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  'drop_index'::text as tag_reco_topic,
  quote_ident(schemaname)||'.'||quote_ident(indexrelname) as tag_object_name,
  ('DROP INDEX ' || quote_ident(schemaname)||'.'||quote_ident(indexrelname) || ';')::text as recommendation,
  'NB! Make sure to also check replica pg_stat_user_indexes.idx_scan count if using them for queries'::text as extra_info
from
  pg_stat_user_indexes
  join
  pg_index using (indexrelid)
where
  idx_scan = 0
  and ((pg_relation_size(indexrelid)::numeric / (pg_database_size(current_database()))) > 0.005 /* 0.5% DB size threshold */
    or indisvalid)
  and not indisprimary
  and not indisreplident
;
$sql$,
'{"prometheus_all_gauge_columns": true}',
true
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs, m_master_only)
values (
'reco_nested_views',
9.1,
$sql$
WITH RECURSIVE views AS (
   -- get the directly depending views
   SELECT v.oid::regclass AS view,
          format('%s.%s', quote_ident(n.nspname), quote_ident(v.relname)) as full_name,
          1 AS level
   FROM pg_depend AS d
      JOIN pg_rewrite AS r
         ON r.oid = d.objid
      JOIN pg_class AS v
         ON v.oid = r.ev_class
      JOIN pg_namespace AS n
         ON n.oid = v.relnamespace
   WHERE v.relkind = 'v'
     AND NOT n.nspname = ANY(array['information_schema', E'pg\\_%'])
     AND NOT v.relname LIKE E'pg\\_%'
     AND d.classid = 'pg_rewrite'::regclass
     AND d.refclassid = 'pg_class'::regclass
     AND d.deptype = 'n'
UNION ALL
   -- add the views that depend on these
   SELECT v.oid::regclass,
          format('%s.%s', quote_ident(n.nspname), quote_ident(v.relname)) as full_name,
          views.level + 1
   FROM views
      JOIN pg_depend AS d
         ON d.refobjid = views.view
      JOIN pg_rewrite AS r
         ON r.oid = d.objid
      JOIN pg_class AS v
         ON v.oid = r.ev_class
      JOIN pg_namespace AS n
         ON n.oid = v.relnamespace
   WHERE v.relkind = 'v'
     AND NOT n.nspname = ANY(array['information_schema', E'pg\\_%'])
     AND d.classid = 'pg_rewrite'::regclass
     AND d.refclassid = 'pg_class'::regclass
     AND d.deptype = 'n'
     AND v.oid <> views.view  -- avoid loop
)
SELECT
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  'overly_nested_views'::text AS tag_reco_topic,
  full_name::text as tag_object_name,
  'overly nested views can affect performance'::text recommendation,
  'nesting_depth: ' || coalesce (max(level)::text, '-') AS extra_info
FROM views
GROUP BY 1, 2, 3
HAVING max(level) > 3
ORDER BY max(level) DESC, full_name::text;
$sql$,
'{"prometheus_all_gauge_columns": true}',
true
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs, m_master_only)
values (
'reco_sprocs_wo_search_path',
9.1,
$sql$
with q_sprocs as (
select
  format('%s.%s', quote_ident(nspname), quote_ident(proname)) as sproc_name,
  'alter function ' || proname || '(' || pg_get_function_arguments(p.oid) || ') set search_path = X;' as fix_sql
from
  pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where prosecdef and not 'search_path' = ANY(coalesce(proconfig, '{}'::text[]))
  and not pg_catalog.obj_description(p.oid, 'pg_proc') ~ 'pgwatch2'
)
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  'sprocs_wo_search_path'::text as tag_reco_topic,
  sproc_name::text as tag_object_name,
  fix_sql::text as recommendation,
  'functions without fixed search_path can be potentially abused by malicious users if used objects are not fully qualified'::text as extra_info
from
  q_sprocs
order by
   tag_object_name, extra_info;
$sql$,
'{"prometheus_all_gauge_columns": true}',
true
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs, m_master_only)
values (
'reco_superusers',
9.1,
$sql$
/* reco_* metrics have special handling - all results are stored actually under one 'recommendations' metric  and
 following text columns are expected:  reco_topic, object_name, recommendation, extra_info.
*/
with q_su as (
  select count(*) from pg_roles where rolcanlogin and rolsuper
),
q_total as (
  select count(*) from pg_roles where rolcanlogin
)
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  'superuser_count'::text as tag_reco_topic,
  '-'::text as tag_object_name,
  'too many superusers detected - review recommended'::text as recommendation,
  format('%s active superusers, %s total active users', q_su.count, q_total.count) as extra_info
from
  q_su, q_total
where
  q_su.count >= 10
;
$sql$,
'{"prometheus_all_gauge_columns": true}',
true
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs, m_master_only)
values (
'reco_disabled_triggers',
9.0,
$sql$
/* "temporarily" disabled triggers might be forgotten about... */
select
    (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
    'disabled_triggers'::text as tag_reco_topic,
    quote_ident(nspname)||'.'||quote_ident(relname) as tag_object_name,
    'review usage of trigger and consider dropping it if not needed anymore'::text as recommendation,
    ''::text as extra_info
from
    pg_trigger t
    join
    pg_class c on c.oid = t.tgrelid
    join
    pg_namespace n on n.oid = c.relnamespace
where
    tgenabled = 'D'
;
$sql$,
'{"prometheus_all_gauge_columns": true}',
true
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs, m_master_only)
values (
'reco_partial_index_candidates',
9.0,
$sql$
select distinct
    (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
    'partial_index_candidates'::text as tag_reco_topic,
    quote_ident(ni.nspname)||'.'||quote_ident(ci.relname) as tag_object_name,
    ('index ' || quote_ident(ni.nspname)||'.'||quote_ident(ci.relname) || ' on ' || quote_ident(s.schemaname) || '.' || quote_ident(s.tablename) || ' column ' || quote_ident(s.attname)  || ' could possibly be declared partial leaving out NULL-s')::text as recommendation,
    'NULL fraction: ' || round((null_frac * 100)::numeric, 1) || '%, rowcount estimate: ' || (c.reltuples)::int8 || ', current definition: ' ||  pg_get_indexdef(i.indexrelid) as extra_info
from
    pg_stats s
    join pg_attribute a using (attname)
    join pg_index i on i.indkey[0] = a.attnum and i.indrelid = a.attrelid
    join pg_class c on c.oid = i.indrelid
    join pg_class ci on ci.oid = i.indexrelid
    join pg_namespace ni on ni.oid = ci.relnamespace
where
  not indisprimary
  and not indisunique
  and indisready
  and indisvalid
  and i.indnatts = 1 /* simple 1 column indexes */
  and null_frac > 0.5 /* 50% empty */
  and not pg_get_indexdef(i.indexrelid) like '% WHERE %'
  and c.reltuples >= 1e5 /* ignore smaller tables */
  and not exists ( /* leave out sub-partitions */
    select * from pg_inherits where inhrelid = c.oid
  )
;
$sql$,
'{"prometheus_all_gauge_columns": true}',
true
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs, m_master_only)
values (
'show_plans_realtime',
9.0,
$sql$
/* assumes pg_show_plans extension */
select
  max((extract(epoch from now()) * 1e9)::int8) as epoch_ns,
  max(extract(epoch from now() - query_start))::int as max_s,
  avg(extract(epoch from now() - query_start))::int as avg_s,
  count(*),
  array_to_string(array_agg(distinct usename order by usename), ',') as "users",
  max(md5(plan)) as tag_hash, /* needed for influx */
  plan,
  max(query) as query
from
  pg_show_plans p
  join
  pg_stat_activity a
    using (pid)
where
  p.pid != pg_backend_pid()
  and datname = current_database()
  and now() - query_start > '1s'::interval
group by
  plan
order by
  max_s desc
limit
  10
;
$sql$,
'{"prometheus_all_gauge_columns": true}',
false
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs, m_master_only)
values (
'show_plans_realtime',
10,
$sql$
/* assumes pg_show_plans extension */
select
  max((extract(epoch from now()) * 1e9)::int8) as epoch_ns,
  max(extract(epoch from now() - query_start))::int as max_s,
  avg(extract(epoch from now() - query_start))::int as avg_s,
  count(*),
  array_to_string(array_agg(distinct usename order by usename), ',') as "users",
  max(md5(plan)) as tag_hash, /* needed for influx */
  plan,
  max(query) as query
from
  pg_show_plans p
  join
  pg_stat_activity a
    using (pid)
where
  p.pid != pg_backend_pid()
  and datname = current_database()
  and now() - query_start > '1s'::interval
  and backend_type = 'client backend'
group by
  plan
order by
  max_s desc
limit
  10
;
$sql$,
'{"prometheus_all_gauge_columns": true}',
false
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs, m_is_helper)
values (
'get_smart_health_per_device',
9.1,
$sql$
CREATE EXTENSION IF NOT EXISTS plpython3u;
/*
  A wrapper around smartmontools to verify disk SMART health for all disk devices. 0 = SMART check PASSED.
  NB! This helper is always meant to be tested / adjusted to make sure all disk are detected etc.
  Most likely smartctl privileges must be escalated to give postgres access: sudo chmod u+s /usr/local/sbin/smartctl
*/
CREATE OR REPLACE FUNCTION get_smart_health_per_device(OUT device text, OUT retcode int) RETURNS SETOF record AS
$$

import subprocess
ret_list = []

#disk_detect_cmd='smartctl --scan | cut -d " " -f3 | grep mega' # for Lenovo ServerRAID M1210
disk_detect_cmd='lsblk -io KNAME,TYPE | grep '' disk'' | cut -d " " -f1 | sort'
p = subprocess.run(disk_detect_cmd, stdout=subprocess.PIPE, encoding='utf-8', shell=True)
if p.returncode != 0:
    return ret_list
disks = p.stdout.splitlines()

for disk in disks:
    # health_cmd = 'smartctl -d $disk -a -q silent /dev/sda' % disk    # for Lenovo ServerRAID M1210 members
    health_cmd = 'smartctl  -a -q silent /dev/%s' % disk
    p = subprocess.run(health_cmd, stdout=subprocess.PIPE, encoding='utf-8', shell=True)
    ret_list.append((disk, p.returncode))

return ret_list

$$ LANGUAGE plpython3u VOLATILE;

GRANT EXECUTE ON FUNCTION get_smart_health_per_device() TO pgwatch2;

COMMENT ON FUNCTION get_smart_health_per_device() is 'created for pgwatch2';
$sql$,
'{"prometheus_all_gauge_columns": true}',
true
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs)
values (
'smart_health_per_disk',
9.1,
$sql$
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  device as tag_device,
  retcode
from
  get_smart_health_per_device();
$sql$,
'{"prometheus_all_gauge_columns": true}'
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs)
values (
'server_log_event_counts',
9.0,
$sql$
/* dummy placeholder - special handling in code */
$sql$,
'{"prometheus_all_gauge_columns": true}'
);


insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_comment, m_is_helper)
values (
'get_backup_age_walg',
9.1,
$sql$
CREATE EXTENSION IF NOT EXISTS plpython3u;
/*
  Gets age of last successful WAL-G backup via "wal-g backup-list" timestamp. Returns 0 retcode on success.
  Expects .wal-g.json is correctly configured with all necessary credentials and "jq" tool is installed on the DB server.
*/
CREATE OR REPLACE FUNCTION get_backup_age_walg(OUT retcode int, OUT backup_age_seconds int, OUT message text) AS
$$
import subprocess
retcode=1
backup_age_seconds=1000000
message=''

# get latest wal-g backup timestamp
walg_last_backup_cmd="""wal-g backup-list --json | jq -r '.[0].time'"""
p = subprocess.run(walg_last_backup_cmd, stdout=subprocess.PIPE, encoding='utf-8', shell=True)
if p.returncode != 0:
    # plpy.notice("p.stdout: " + str(p.stderr) + str(p.stderr))
    return p.returncode, backup_age_seconds, 'Not OK. Failed on wal-g backup-list call'

# plpy.notice("last_tz: " + last_tz)
last_tz=p.stdout.rstrip('\n\r')

# get seconds since last backup from WAL-G timestamp in format '2020-01-22T17:50:51Z'
try:
    plan = plpy.prepare("SELECT extract(epoch from now() - $1::timestamptz)::int AS backup_age_seconds;", ["text"])
    rv = plpy.execute(plan, [last_tz])
except Exception as e:
    return retcode, backup_age_seconds, 'Not OK. Failed to convert WAL-G backup timestamp to seconds'
else:
    backup_age_seconds = rv[0]["backup_age_seconds"]
    return 0, backup_age_seconds, 'OK. Last backup age in seconds: %s' % backup_age_seconds

$$ LANGUAGE plpython3u VOLATILE;

/* contacting S3 could be laggy depending on location */
ALTER FUNCTION get_backup_age_walg() SET statement_timeout TO '30s';

GRANT EXECUTE ON FUNCTION get_backup_age_walg() TO pgwatch2;

COMMENT ON FUNCTION get_backup_age_walg() is 'created for pgwatch2';

$sql$,
'for internal usage - when connecting user is marked as superuser then the daemon will automatically try to create the needed helpers on the monitored db',
true
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs)
values (
'backup_age_walg',
9.1,
$sql$
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  retcode,
  backup_age_seconds,
  message
from
  get_backup_age_walg()
;
$sql$,
'{"prometheus_all_gauge_columns": true}'
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_comment, m_is_helper)
values (
'get_backup_age_pgbackrest',
9.1,
$sql$

CREATE EXTENSION IF NOT EXISTS plpython3u;
/*
  Gets age of last successful pgBackRest backup via "pgbackrest --output=json info" unix timestamp. Returns 0 retcode on success.
  Expects pgBackRest is correctly configured on monitored DB and "jq" tool is installed on the DB server.
*/
CREATE OR REPLACE FUNCTION get_backup_age_pgbackrest(OUT retcode int, OUT backup_age_seconds int, OUT message text) AS
$$
import subprocess
retcode=1
backup_age_seconds=1000000
message=''

# get latest wal-g backup timestamp
walg_last_backup_cmd="""pgbackrest --output=json info | jq '.[0] | .backup[-1] | .timestamp.stop'"""
p = subprocess.run(walg_last_backup_cmd, stdout=subprocess.PIPE, encoding='utf-8', shell=True)
if p.returncode != 0:
    # plpy.notice("p.stdout: " + str(p.stderr) + str(p.stderr))
    return p.returncode, backup_age_seconds, 'Not OK. Failed on "pgbackrest info" call'

last_backup_stop_epoch=p.stdout.rstrip('\n\r')

try:
    plan = plpy.prepare("SELECT (extract(epoch from now()) - $1)::int8 AS backup_age_seconds;", ["int8"])
    rv = plpy.execute(plan, [last_backup_stop_epoch])
except Exception as e:
    return retcode, backup_age_seconds, 'Not OK. Failed to extract seconds difference via Postgres'
else:
    backup_age_seconds = rv[0]["backup_age_seconds"]
    return 0, backup_age_seconds, 'OK. Last backup age in seconds: %s' % backup_age_seconds

$$ LANGUAGE plpython3u VOLATILE;

/* contacting S3 could be laggy depending on location */
ALTER FUNCTION get_backup_age_pgbackrest() SET statement_timeout TO '30s';

GRANT EXECUTE ON FUNCTION get_backup_age_pgbackrest() TO pgwatch2;

COMMENT ON FUNCTION get_backup_age_pgbackrest() is 'created for pgwatch2';

$sql$,
'for internal usage - when connecting user is marked as superuser then the daemon will automatically try to create the needed helpers on the monitored db',
true
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs)
values (
'backup_age_pgbackrest',
9.1,
$sql$
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  retcode,
  backup_age_seconds,
  message
from
  get_backup_age_pgbackrest()
;
$sql$,
'{"prometheus_all_gauge_columns": true}'
);


insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs)
values (
'logical_subscriptions',
10,
$sql$
with q_sr as (
  select * from pg_subscription_rel
)
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  subname::text as tag_subname,
  subenabled,
  (select count(*) from q_sr where srsubid = oid) as relcount,
  (select count(*) from q_sr where srsubid = oid and srsubstate = 'i') as state_i,
  (select count(*) from q_sr where srsubid = oid and srsubstate = 'd') as state_d,
  (select count(*) from q_sr where srsubid = oid and srsubstate = 's') as state_s,
  (select count(*) from q_sr where srsubid = oid and srsubstate = 'r') as state_r
from
  pg_subscription
where
  subdbid = (select oid from pg_database where datname = current_database())
;
$sql$,
'{"prometheus_all_gauge_columns": true}'
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_comment, m_is_helper)
values (
'get_vmstat',
9.1,
$sql$
/*
  vmstat + some extra infos like CPU count, 1m/5m/15m load avg. and total memory
  NB! Memory and disk info returned in bytes!
*/

CREATE EXTENSION IF NOT EXISTS plpython3u; /* NB! "plpython3u" might need changing to "plpythonu" (Python 2) everywhere for older OS-es */

-- DROP FUNCTION get_vmstat(int);

CREATE OR REPLACE FUNCTION get_vmstat(
    IN delay int default 1,
    OUT r int, OUT b int, OUT swpd int8, OUT free int8, OUT buff int8, OUT cache int8, OUT si int8, OUT so int8, OUT bi int8,
    OUT bo int8, OUT "in" int, OUT cs int, OUT us int, OUT sy int, OUT id int, OUT wa int, OUT st int,
    OUT cpu_count int, OUT load_1m float4, OUT load_5m float4, OUT load_15m float4, OUT total_memory int8
)
    LANGUAGE plpython3u
AS $FUNCTION$
    from os import cpu_count, popen
    unit = 1024  # 'vmstat' default block byte size

    cpu_count = cpu_count()
    vmstat_lines = popen('vmstat {} 2'.format(delay)).readlines()
    vm = [int(x) for x in vmstat_lines[-1].split()]
    # plpy.notice(vm)
    load_1m, load_5m, load_15m = None, None, None
    with open('/proc/loadavg', 'r') as f:
        la_line = f.readline()
        if la_line:
            splits = la_line.split()
            if len(splits) == 5:
                load_1m, load_5m, load_15m = splits[0], splits[1], splits[2]

    total_memory = None
    with open('/proc/meminfo', 'r') as f:
        mi_line = f.readline()
        splits = mi_line.split()
        # plpy.notice(splits)
        if len(splits) == 3:
            total_memory = int(splits[1]) * 1024

    return vm[0], vm[1], vm[2] * unit, vm[3] * unit, vm[4] * unit, vm[5] * unit, vm[6] * unit, vm[7] * unit, vm[8] * unit, \
        vm[9] * unit, vm[10], vm[11], vm[12], vm[13], vm[14], vm[15], vm[16], cpu_count, load_1m, load_5m, load_15m, total_memory
$FUNCTION$;

GRANT EXECUTE ON FUNCTION get_vmstat(int) TO pgwatch2;
COMMENT ON FUNCTION get_vmstat(int) IS 'created for pgwatch2';

$sql$,
'',
true
);


insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_column_attrs)
values (
'vmstat',
9.1,
$sql$
SELECT
    (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
    r, b, swpd, free, buff, cache, si, so, bi, bo, "in", cs, us, sy, id, wa, st, cpu_count, load_1m, load_5m, load_15m, total_memory
from
    get_vmstat();
$sql$,
'{"prometheus_all_gauge_columns": true}'
);


insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_comment)
values (
'instance_up',
9.0,
$sql$
select
    (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
    1::int as is_up
;
$sql$,
'NB! This metric has some special handling attached to it - it will store a 0 value if the DB is not accessible.
Thus it can be used to for example calculate some percentual "uptime" indicator.'
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_is_helper, m_sql)
values (
'get_sequences',
10,
true,
$sql$
CREATE OR REPLACE FUNCTION get_sequences() RETURNS SETOF pg_sequences AS
$$
  select * from pg_sequences
$$ LANGUAGE sql VOLATILE SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_sequences() TO pgwatch2;
COMMENT ON FUNCTION get_sequences() IS 'created for pgwatch2';
$sql$
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_sql_su)
values (
'sequence_health',
10,
$sql$
with q_seq_data as (
    select * from get_sequences()
)
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  (select round(100.0 * coalesce(max(last_value::numeric / max_value), 0), 2)::float from q_seq_data where not cycle) as max_used_pct,
  (select count(*) from q_seq_data where not cycle and last_value::numeric / max_value > 0.5) as p50_used_seq_count,
  (select count(*) from q_seq_data where not cycle and last_value::numeric / max_value > 0.75) as p75_used_seq_count;
$sql$,
$sql$
with q_seq_data as (
    select * from pg_sequences
)
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  (select round(100.0 * coalesce(max(last_value::numeric / max_value), 0), 2)::float from q_seq_data where not cycle) as max_used_pct,
  (select count(*) from q_seq_data where not cycle and last_value::numeric / max_value > 0.5) as p50_used_seq_count,
  (select count(*) from q_seq_data where not cycle and last_value::numeric / max_value > 0.75) as p75_used_seq_count;
$sql$
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql)
values (
'replication_slot_stats',
14,
$sql$
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  slot_name::text as tag_slot_name,
  spill_txns,
  spill_count,
  spill_bytes,
  stream_txns,
  stream_count,
  stream_bytes,
  total_txns,
  total_bytes
from
  pg_stat_replication_slots;
$sql$
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql)
values (
'wal_stats',
14,
$sql$
select
    (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
    wal_records,
    wal_fpi,
    (wal_bytes / 1024)::int8 as wal_bytes_kb,
    wal_buffers_full,
    wal_write,
    wal_sync,
    wal_write_time::int8,
    wal_sync_time::int8
from
    pg_stat_wal;
$sql$
);


insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql)
values (
'wait_events',
9.6,
$sql$
  with q_sa as (
      select * from pg_stat_activity where datname = current_database() and pid <> pg_backend_pid()
  )
  select
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
$sql$
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql)
values (
'subscription_stats',
15,
$sql$
select /* pgwatch2_generated */
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  subname::text as tag_subname,
  apply_error_count,
  sync_error_count
from
  pg_stat_subscription_stats;
$sql$
);

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql, m_sql_su)
values (
'stat_activity',
10,
$sql$
select /* pgwatch2_generated */
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  s.query as query,
  count(*) as count
from get_stat_activity() s
where s.datname = current_database()
  and s.state = 'active'
  and s.backend_type = 'client backend'
  and s.pid != pg_backend_pid()
  and now() - s.query_start > '100ms'::interval
group by s.query;
$sql$,
$sql$
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
$sql$);

/* stat_io (v16+) */

insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql)
values (
'stat_io',
16,
$sql$
 SELECT /* pgwatch2_generated */
    (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
    coalesce(backend_type, 'total') as tag_backend_type,
    sum(coalesce(reads, 0))::int8  as reads,
    (sum(coalesce(reads, 0) * op_bytes) / 1e6)::int8 as read_bytes_mb,
    sum(coalesce(read_time, 0))::int8 as read_time_ms,
    sum(coalesce(writes, 0))::int8 as writes,
    (sum(coalesce(writes, 0) * op_bytes) / 1e6)::int8 as write_bytes_mb,
    sum(coalesce(write_time, 0))::int8 as write_time_ms,
    sum(coalesce(writebacks, 0))::int8 as writebacks,
    (sum(coalesce(writebacks, 0) * op_bytes) / 1e6)::int8 as writeback_bytes_mb,
    sum(coalesce(writeback_time, 0))::int8 as writeback_time_ms,
    sum(coalesce(fsyncs, 0))::int8 fsyncs,
    sum(coalesce(fsync_time, 0))::int8 fsync_time_ms,
    max(extract(epoch from now() - stats_reset)::int) as stats_reset_s
FROM
    pg_stat_io
GROUP BY
   ROLLUP (backend_type);
$sql$);


insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql)
values (
'unused_indexes',
10,
$sql$
select /* pgwatch2_generated */
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  *
from (
  select
    format('%I.%I', sui.schemaname, sui.indexrelname) as tag_index_full_name,
    sui.idx_scan,
    coalesce(pg_relation_size(sui.indexrelid), 0) as index_size_b,
    system_identifier::text as tag_sys_id /* to easily check also all replicas as could be still used there */
  from
    pg_stat_user_indexes sui
    join pg_index i on i.indexrelid = sui.indexrelid
    join pg_control_system() on true
  where not sui.schemaname like E'pg\\_temp%'
  and idx_scan = 0
  and not (indisprimary or indisunique or indisexclusion)
  and not exists (select * from pg_locks where relation = sui.relid and mode = 'AccessExclusiveLock')
) x
where index_size_b > 100*1024^2 /* list >100MB only */
order by index_size_b desc
limit 25;
$sql$);


insert into pgwatch2.metric(m_name, m_pg_version_from, m_sql)
values (
'invalid_indexes',
10,
$sql$
select /* pgwatch2_generated */
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  format('%I.%I', n.nspname , ci.relname) as tag_index_full_name,
  coalesce(pg_relation_size(indexrelid), 0) as index_size_b
from
  pg_index i
  join pg_class ci on ci.oid = i.indexrelid
  join pg_class cr on cr.oid = i.indrelid
  join pg_namespace n on n.oid = ci.relnamespace
where not n.nspname like E'pg\\_temp%'
and not indisvalid
and not exists ( /* leave out ones that are being actively rebuilt */
  select * from pg_locks l
  join pg_stat_activity a using (pid)
  where l.relation = i.indexrelid
  and a.state = 'active'
  and a.query ~* 'concurrently'
)
and not exists (select * from pg_locks where relation = indexrelid and mode = 'AccessExclusiveLock') /* can't get size then */
order by index_size_b desc
limit 100;
$sql$);


/* Metric attributes */
-- truncate pgwatch2.metric_attribute;

-- mark instance level metrics for metrics defined by pgwatch, enables stats caching / sharing for multi-DB instances
insert into pgwatch2.metric_attribute (ma_metric_name, ma_metric_attrs)
select m, '{"is_instance_level": true}'
from unnest(
   array['archiver', 'backup_age_pgbackrest', 'backup_age_walg', 'bgwriter', 'buffercache_by_db', 'buffercache_by_type',
  'cpu_load', 'psutil_cpu', 'psutil_disk', 'psutil_disk_io_total', 'psutil_mem', 'replication', 'replication_slots',
  'smart_health_per_disk', 'stat_io', 'wal', 'wal_receiver', 'wal_size']
) m
on conflict (ma_metric_name)
do update set ma_metric_attrs = pgwatch2.metric_attribute.ma_metric_attrs || '{"is_instance_level": true}', ma_last_modified_on = now();

-- dynamic re-routing of metric names
insert into pgwatch2.metric_attribute (ma_metric_name, ma_metric_attrs)
select 'stat_statements_no_query_text', '{"metric_storage_name": "stat_statements", "prerequisite_extensions": ["pg_stat_statements"]}'
on conflict (ma_metric_name)
do update set ma_metric_attrs = pgwatch2.metric_attribute.ma_metric_attrs || '{"metric_storage_name": "stat_statements", "prerequisite_extensions": ["pg_stat_statements"]}', ma_last_modified_on = now();

insert into pgwatch2.metric_attribute (ma_metric_name, ma_metric_attrs)
select 'stat_statements', '{"prerequisite_extensions": ["pg_stat_statements"]}'
on conflict (ma_metric_name)
do update set ma_metric_attrs = pgwatch2.metric_attribute.ma_metric_attrs || '{"prerequisite_extensions": ["pg_stat_statements"]}', ma_last_modified_on = now();

insert into pgwatch2.metric_attribute (ma_metric_name, ma_metric_attrs)
select 'stat_statements_calls', '{"prerequisite_extensions": ["pg_stat_statements"]}'
on conflict (ma_metric_name)
do update set ma_metric_attrs = pgwatch2.metric_attribute.ma_metric_attrs || '{"prerequisite_extensions": ["pg_stat_statements"]}', ma_last_modified_on = now();

insert into pgwatch2.metric_attribute (ma_metric_name, ma_metric_attrs)
select 'db_stats_aurora', '{"metric_storage_name": "db_stats"}'
on conflict (ma_metric_name)
do update set ma_metric_attrs = pgwatch2.metric_attribute.ma_metric_attrs || '{"metric_storage_name": "db_stats"}', ma_last_modified_on = now();

insert into pgwatch2.metric_attribute (ma_metric_name, ma_metric_attrs)
select 'db_size_approx', '{"metric_storage_name": "db_size_approx"}'
on conflict (ma_metric_name)
do update set ma_metric_attrs = pgwatch2.metric_attribute.ma_metric_attrs || '{"metric_storage_name": "db_size_approx"}', ma_last_modified_on = now();

insert into pgwatch2.metric_attribute (ma_metric_name, ma_metric_attrs)
select 'table_stats_approx', '{"metric_storage_name": "table_stats"}'
on conflict (ma_metric_name)
do update set ma_metric_attrs = pgwatch2.metric_attribute.ma_metric_attrs || '{"metric_storage_name": "table_stats"}', ma_last_modified_on = now();

insert into pgwatch2.metric_attribute (ma_metric_name, ma_metric_attrs)
select 'reco_add_index', '{"extension_version_based_overrides": [{"target_metric": "reco_add_index_ext_qualstats_2.0", "expected_extension_versions": [{"ext_name": "pg_qualstats", "ext_min_version": "2.0"}] }]}'
on conflict (ma_metric_name)
do update set ma_metric_attrs = pgwatch2.metric_attribute.ma_metric_attrs || '{"extension_version_based_overrides": [{"target_metric": "reco_add_index_ext_qualstats_2.0", "expected_extension_versions": [{"ext_name": "pg_qualstats", "ext_min_version": "2.0"}] }]}', ma_last_modified_on = now();
