select /* pgwatch2_generated */
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  retcode,
  backup_age_seconds,
  message
from
  get_backup_age_pgbackrest()
;