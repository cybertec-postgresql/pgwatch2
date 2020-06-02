SELECT
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  application_name as tag_application_name,
  concat(coalesce(client_addr::text, client_hostname), '_', client_port::text) as tag_client_info,
  coalesce(pg_wal_lsn_diff(pg_current_wal_lsn(), write_lsn)::int8, 0) as write_lag_b,
  coalesce(pg_wal_lsn_diff(pg_current_wal_lsn(), flush_lsn)::int8, 0) as flush_lag_b,
  coalesce(pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn)::int8, 0) as replay_lag_b,
  state,
  sync_state,
  case when sync_state in ('sync', 'quorum') then 1 else 0 end as is_sync_int,
  spill_bytes
from
  /* NB! when the query fails, grant "pg_monitor" system role (exposing all stats) to the monitoring user
     or create specifically the "get_stat_replication" helper and use that instead of pg_stat_replication
  */
  pg_stat_replication;
