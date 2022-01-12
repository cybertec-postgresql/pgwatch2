select /* pgwatch2_generated */
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  pg_wal_lsn_diff(pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn())::int8 as replay_lag_b,
  extract(epoch from (now() - pg_last_xact_replay_timestamp()))::int8 as last_replay_s;
