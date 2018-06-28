WITH q_stat_tables AS (
  SELECT * FROM pg_stat_user_tables t
  JOIN pg_class c ON c.oid = t.relid
  WHERE NOT schemaname LIKE E'pg\\_temp%'
  AND c.relpages > (1e7 / 8)    -- >10MB
),
q_stat_activity AS (
  SELECT * FROM public.get_stat_activity() WHERE pid != pg_backend_pid() AND datname = current_database()
)
SELECT
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  (select pg_xlog_location_diff(pg_current_xlog_location(), '0/0'))::int8 AS wal_location_b,
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
  (select sum(seq_scan) from q_stat_tables) AS seq_scans_on_tbls_gt_10mb,
  tup_inserted,
  tup_updated,
  tup_deleted,
  (select sum(calls) from pg_stat_user_functions where not schemaname like any(array[E'pg\\_%', 'information_schema'])) AS sproc_calls,
  blk_read_time,
  blk_write_time,
  deadlocks
FROM
  pg_stat_database d
WHERE
  datname = current_database();
