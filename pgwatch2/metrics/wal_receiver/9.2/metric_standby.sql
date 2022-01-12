select /* pgwatch2_generated */
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  pg_xlog_location_diff(pg_last_xlog_receive_location(), pg_last_xlog_replay_location())::int8 as replay_lag_b,
  extract(epoch from (now() - pg_last_xact_replay_timestamp()))::int8 as last_replay_s;
