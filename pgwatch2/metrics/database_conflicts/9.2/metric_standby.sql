select /* pgwatch2_generated */
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  confl_tablespace,
  confl_lock,
  confl_snapshot,
  confl_bufferpin,
  confl_deadlock
FROM
  pg_stat_database_conflicts
WHERE
  datname = current_database();
