select /* pgwatch2_generated */
    (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
    pid as tag_pid,
    usename::text AS user,
    application_name AS appname,
    coalesce(client_addr::text, 'local') AS ip,
    extract(epoch FROM (now() - query_start))::int AS duration_s,
    (wait_event_type IS NOT NULL)::int AS waiting,
    array_to_string(pg_blocking_pids(pid), ',') as blocking_pids,
    ltrim(regexp_replace(query, E'[ \\t\\n\\r]+' , ' ', 'g'))::varchar(300) AS query
FROM
    pg_stat_activity
WHERE
  state != 'idle'
  AND pid != pg_backend_pid()
  AND datname = current_database()
  AND now() - query_start > '500ms'::interval
ORDER BY
  now() - query_start DESC
LIMIT 25;
