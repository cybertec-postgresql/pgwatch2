select /* pgwatch2_generated */
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
  --
  pg_stat_replication
where
  coalesce(application_name, '') not in ('pg_basebackup', 'pg_rewind');
