select /* pgwatch2_generated */
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  slot_name::text as tag_slot_name,
  coalesce(plugin, 'physical')::text as tag_plugin,
  active,
  case when active then 0 else 1 end as non_active_int,
  case when not pg_is_in_recovery() then pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)::int8
  else pg_wal_lsn_diff(pg_last_wal_replay_lsn(), restart_lsn)::int8 end as restart_lsn_lag_b,
  case when not pg_is_in_recovery() then pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn)::int8
  else pg_wal_lsn_diff(pg_last_wal_replay_lsn(), confirmed_flush_lsn)::int8 end as confirmed_flush_lsn_lag_b,
  greatest(age(xmin), age(catalog_xmin))::int8 as xmin_age_tx
from
  pg_replication_slots;
