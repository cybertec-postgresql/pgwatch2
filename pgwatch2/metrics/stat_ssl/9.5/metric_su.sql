SELECT
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  ssl,
  count(*)
FROM
  pg_stat_ssl AS s,
  pg_stat_activity AS a
WHERE
  a.pid = s.pid
  AND a.datname = current_database()
GROUP BY
  1, 2;
