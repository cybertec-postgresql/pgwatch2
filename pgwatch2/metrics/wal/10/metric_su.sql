select /* pgwatch2_generated */
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  case
    when pg_is_in_recovery() = false then
      pg_wal_lsn_diff(pg_current_wal_lsn(), '0/0')::int8
    else
      pg_wal_lsn_diff(pg_last_wal_replay_lsn(), '0/0')::int8
    end as xlog_location_b,
  case when pg_is_in_recovery() then 1 else 0 end as in_recovery_int,
  extract(epoch from (now() - coalesce((pg_stat_file('postmaster.pid', true)).modification, pg_postmaster_start_time())))::int8 as postmaster_uptime_s,
  system_identifier::text as tag_sys_id,
  case
    when pg_is_in_recovery() = false then
      ('x'||substr(pg_walfile_name(pg_current_wal_lsn()), 1, 8))::bit(32)::int
    else
      (select min_recovery_end_timeline::int from pg_control_recovery())
    end as timeline
from pg_control_system();
