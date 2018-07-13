select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  slot_name::text as tag_slot_name,
  coalesce(plugin, 'physical')::text as tag_plugin,
  active,
  pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) as restart_lsn_lag_b
from
  pg_replication_slots;
