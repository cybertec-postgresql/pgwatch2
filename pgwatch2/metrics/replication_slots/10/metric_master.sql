select /* pgwatch2_generated */
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  slot_name::text as tag_slot_name,
  coalesce(plugin, 'physical')::text as tag_plugin,
  active,
  case when active then 0 else 1 end as non_active_int,
  pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)::int8 as restart_lsn_lag_b,
  pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn)::int8 as confirmed_flush_lsn_lag_b,
  greatest(age(xmin), age(catalog_xmin))::int8 as xmin_age_tx
from
  pg_replication_slots;
