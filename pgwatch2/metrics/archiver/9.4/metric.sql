select /* pgwatch2_generated */
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  archived_count,
  failed_count,
  case when coalesce(last_failed_time, '1970-01-01'::timestamptz) > coalesce(last_archived_time, '1970-01-01'::timestamptz) then 1 else 0 end as is_failing_int,
  extract(epoch from now() - last_failed_time)::int8 as seconds_since_last_failure
from
  pg_stat_archiver
where
  current_setting('archive_mode') in ('on', 'always');
