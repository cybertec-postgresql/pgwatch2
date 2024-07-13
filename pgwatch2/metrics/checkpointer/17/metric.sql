select /* pgwatch2_generated */
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  num_timed,
  num_requested,
  restartpoints_timed,
  restartpoints_req,
  restartpoints_done,
  write_time,
  sync_time,
  buffers_written,
  (extract(epoch from now() - stats_reset))::int as last_reset_s
from
  pg_stat_checkpointer;
