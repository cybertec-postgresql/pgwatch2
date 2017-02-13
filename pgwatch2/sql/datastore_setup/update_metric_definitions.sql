
update pgwatch2.metric
set m_sql = $sql$
with sa_snapshot as (
  select * from pg_stat_activity where pid != pg_backend_pid() and not query like 'autovacuum:%' and datname = current_database()
)
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  (select count(*) from sa_snapshot) as total,
  (select count(*) from sa_snapshot where state = 'active') as active,
  (select count(*) from sa_snapshot where state = 'idle') as idle,
  (select count(*) from sa_snapshot where state = 'idle in transaction') as idleintransaction,
  (select count(*) from sa_snapshot where wait_event_type is not null) as waiting,
  (select extract(epoch from (now() - backend_start))::int
    from sa_snapshot order by backend_start limit 1) as longest_session_seconds,
  (select extract(epoch from (now() - xact_start))::int
    from sa_snapshot where xact_start is not null order by xact_start limit 1) as longest_tx_seconds,
  (select extract(epoch from max(now() - query_start))::int
    from sa_snapshot where state = 'active') as longest_query_seconds;
$sql$
where m_name = 'backends' and  m_pg_version_from = 9.6
;

update pgwatch2.metric
set m_sql = $sql$
with sa_snapshot as (
  select * from pg_stat_activity where pid != pg_backend_pid() and not query like 'autovacuum:%' and datname = current_database()
)
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  (select count(*) from sa_snapshot) as total,
  (select count(*) from sa_snapshot where state = 'active') as active,
  (select count(*) from sa_snapshot where state = 'idle') as idle,
  (select count(*) from sa_snapshot where state = 'idle in transaction') as idleintransaction,
  (select count(*) from sa_snapshot where waiting) as waiting,
  (select extract(epoch from (now() - backend_start))::int
    from sa_snapshot order by backend_start limit 1) as longest_session_seconds,
  (select extract(epoch from (now() - xact_start))::int
    from sa_snapshot where xact_start is not null order by xact_start limit 1) as longest_tx_seconds,
  (select extract(epoch from max(now() - query_start))::int
    from sa_snapshot where state = 'active') as longest_query_seconds;
$sql$
where m_name = 'backends' and  m_pg_version_from = 9.0
;


update pgwatch2.metric
set m_sql = $sql$
SELECT
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  application_name as tag_application_name,
  pg_xlog_location_diff(pg_current_xlog_location(), replay_location)::int8 as lag_b,
  coalesce(client_addr::text, client_hostname) as client_info,
  state
from
  pg_stat_replication;
$sql$
where m_name = 'replication';

