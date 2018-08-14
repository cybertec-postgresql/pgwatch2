select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  case
    when pg_is_in_recovery() = false then
      pg_wal_lsn_diff(pg_current_wal_lsn(), '0/0')::int8
    else
      pg_wal_lsn_diff(pg_last_wal_replay_lsn(), '0/0')::int8
    end as xlog_location_b;
