select /* pgwatch2_generated */
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
