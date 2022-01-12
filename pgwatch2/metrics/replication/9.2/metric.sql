select /* pgwatch2_generated */
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

