SELECT
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  application_name as tag_application_name,
  coalesce(pg_xlog_location_diff(pg_current_xlog_location(), replay_location)::int8, 0) as lag_b,
  coalesce(client_addr::text, client_hostname) as client_info,
  state
from
  pg_stat_replication;
