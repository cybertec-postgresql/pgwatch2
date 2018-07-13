SELECT
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  application_name as tag_application_name,
  coalesce(client_addr::text, client_hostname) as tag_client_info,
  coalesce(pg_xlog_location_diff(pg_current_xlog_location(), write_location)::int8, 0) as write_lag_b,
  coalesce(pg_xlog_location_diff(pg_current_xlog_location(), replay_location)::int8, 0) as replay_lag_b,
  state
from
  pg_stat_replication;
