with sa_snapshot as (
  select * from pg_stat_activity
  where datname = current_database()
  and not current_query like 'autovacuum:%'
  and procpid != pg_backend_pid()
)
select
    (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
    (select count(*) from sa_snapshot) as total,
    (select count(*) from sa_snapshot where current_query != '<IDLE>') as active,
    (select count(*) from sa_snapshot where current_query = '<IDLE>') as idle,
    (select count(*) from sa_snapshot where current_query = '<IDLE> in transaction') as idleintransaction,
    (select count(*) from sa_snapshot where waiting) as waiting,
    (select extract(epoch from (now() - backend_start))::int
     from sa_snapshot order by backend_start limit 1) as longest_session_seconds,
    (select extract(epoch from (now() - xact_start))::int
     from sa_snapshot where xact_start is not null order by xact_start limit 1) as longest_tx_seconds,
    (select extract(epoch from (now() - xact_start))::int
     from pg_stat_activity where current_query like 'autovacuum:%' order by xact_start limit 1) as longest_autovacuum_seconds,
    (select extract(epoch from max(now() - query_start))::int
     from sa_snapshot where current_query != '<IDLE>') as longest_query_seconds;
