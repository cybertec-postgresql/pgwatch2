SELECT
    (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
    procpid AS pid,
    usename::text AS user,
    extract(epoch FROM (now() - query_start))::int AS duration_s,
    waiting::int,
    ltrim(regexp_replace(current_query, E'[ \\t\\n\\r]+' , ' ', 'g'))::varchar(200) AS query
FROM
    pg_stat_activity
WHERE
    current_query <> '<IDLE>'
    AND procpid <> pg_backend_pid()
    AND datname = current_database()
    AND NOW() - query_start > '500ms'::interval
ORDER BY
    NOW() - query_start DESC
LIMIT 25;
