select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  pg_database_size(datname) as size_b,
  numbackends,
  xact_commit,
  xact_rollback,
  blks_read,
  blks_hit,
  tup_returned,
  tup_fetched,
  tup_inserted,
  tup_updated,
  tup_deleted,
  conflicts,
  temp_files,
  temp_bytes,
  deadlocks,
  blk_read_time,
  blk_write_time
from
  pg_stat_database
where
  datname = current_database();
