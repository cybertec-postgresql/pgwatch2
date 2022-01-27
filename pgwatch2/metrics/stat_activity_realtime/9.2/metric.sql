select /* pgwatch2_generated */
    (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
    pid as tag_pid,
    usename::text AS user,
    application_name AS appname,
    coalesce(client_addr::text, 'local') AS ip,
    extract(epoch FROM (now() - query_start))::int AS duration_s,
    waiting::int,
    case when sa.waiting then
        (select array_to_string((select array_agg(distinct b.pid order by b.pid) from pg_locks b join pg_locks l on l.database = b.database and l.relation = b.relation
           where l.pid = sa.pid and b.pid != l.pid and b.granted and not l.granted), ','))
        else
            null
    end as blocking_pids,
    ltrim(regexp_replace(query, E'[ \\t\\n\\r]+' , ' ', 'g'))::varchar(300) AS query
FROM
    pg_stat_activity sa
WHERE
    state != 'idle'
    AND pid != pg_backend_pid()
    AND datname = current_database()
    AND now() - query_start > '500ms'::interval
ORDER BY
    now() - query_start DESC
LIMIT 25;
