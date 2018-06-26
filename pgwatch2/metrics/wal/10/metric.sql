select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  pg_wal_lsn_diff(pg_current_wal_lsn(), '0/0')::int8 AS xlog_location_b;
