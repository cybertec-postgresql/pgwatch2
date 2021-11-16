select /* pgwatch2_generated */
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  count(*) as total,
  count(*) FILTER (WHERE ssl) as "on",
  count(*) FILTER (WHERE NOT ssl) as "off"
FROM
  pg_stat_ssl AS s,
  pg_stat_activity AS a
WHERE
  a.pid = s.pid
  AND a.datname = current_database()
  AND a.pid <> pg_backend_pid()
  AND NOT (a.client_addr = '127.0.0.1' OR client_port = -1)
;
