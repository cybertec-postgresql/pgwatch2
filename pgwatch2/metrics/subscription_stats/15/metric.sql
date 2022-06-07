select /* pgwatch2_generated */
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  subname::text as tag_subname,
  apply_error_count,
  sync_error_count
from
  pg_stat_subscription_stats;
