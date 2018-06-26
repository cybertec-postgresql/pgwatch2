select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  pg_xlog_location_diff(pg_current_xlog_location(), '0/0')::int8 AS xlog_location_b;
