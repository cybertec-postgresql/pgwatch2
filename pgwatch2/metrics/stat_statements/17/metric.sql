WITH /* pgwatch2_generated */ q_data AS (
    SELECT
        queryid::text AS tag_queryid,
        /*
         NB! if security conscious about exposing query texts replace the below expression with a dash ('-') OR
         use the stat_statements_no_query_text metric instead, created specifically for this use case.
         */
        array_to_string(array_agg(DISTINCT quote_ident(pg_get_userbyid(userid))), ',') AS users,
        sum(s.calls)::int8 AS calls,
        round(sum(s.total_exec_time)::numeric, 3)::double precision AS total_time,
        sum(shared_blks_hit)::int8 AS shared_blks_hit,
        sum(shared_blks_read)::int8 AS shared_blks_read,
        sum(shared_blks_written)::int8 AS shared_blks_written,
        sum(shared_blks_dirtied)::int8 AS shared_blks_dirtied,
        sum(temp_blks_read)::int8 AS temp_blks_read,
        sum(temp_blks_written)::int8 AS temp_blks_written,
        round((sum(shared_blk_read_time) + sum(local_blk_read_time))::numeric, 3)::double precision AS blk_read_time,
        round((sum(shared_blk_write_time) + sum(local_blk_write_time))::numeric, 3)::double precision AS blk_write_time,
        round(sum(temp_blk_read_time)::numeric, 3)::double precision AS temp_blk_read_time,
        round(sum(temp_blk_write_time)::numeric, 3)::double precision AS temp_blk_write_time,
        sum(wal_fpi)::int8 AS wal_fpi,
        sum(wal_bytes)::int8 AS wal_bytes,
        round(sum(s.total_plan_time)::numeric, 3)::double precision AS total_plan_time,
        max(query::varchar(8000)) AS query
    FROM
        get_stat_statements() s
    WHERE
        calls > 5
        AND total_exec_time > 5
        AND dbid = (
            SELECT
                oid
            FROM
                pg_database
            WHERE
                datname = current_database())
            AND NOT upper(s.query::varchar(50))
            LIKE ANY (ARRAY['DEALLOCATE%',
                'SET %',
                'RESET %',
                'BEGIN%',
                'BEGIN;',
                'COMMIT%',
                'END%',
                'ROLLBACK%',
                'SHOW%'])
        GROUP BY
            queryid
)
SELECT
    (EXTRACT(epoch FROM now()) * 1e9)::int8 AS epoch_ns,
    b.tag_queryid,
    b.users,
    b.calls,
    b.total_time,
    b.shared_blks_hit,
    b.shared_blks_read,
    b.shared_blks_written,
    b.shared_blks_dirtied,
    b.temp_blks_read,
    b.temp_blks_written,
    b.blk_read_time,
    b.blk_write_time,
    b.temp_blk_read_time,
    b.temp_blk_write_time,
    b.wal_fpi,
    b.wal_bytes,
    b.total_plan_time,
    ltrim(regexp_replace(b.query, E'[ \\t\\n\\r]+', ' ', 'g')) AS tag_query
FROM (
    SELECT
        *
    FROM (
        SELECT
            *
        FROM
            q_data
        WHERE
            total_time > 0
        ORDER BY
            total_time DESC
        LIMIT 100) a
UNION
SELECT
    *
FROM (
    SELECT
        *
    FROM
        q_data
    ORDER BY
        calls DESC
    LIMIT 100) a
UNION
SELECT
    *
FROM (
    SELECT
        *
    FROM
        q_data
    WHERE
        shared_blks_read > 0
    ORDER BY
        shared_blks_read DESC
    LIMIT 100) a
UNION
SELECT
    *
FROM (
    SELECT
        *
    FROM
        q_data
    WHERE
        shared_blks_written > 0
    ORDER BY
        shared_blks_written DESC
    LIMIT 100) a
UNION
SELECT
    *
FROM (
    SELECT
        *
    FROM
        q_data
    WHERE
        temp_blks_read > 0
    ORDER BY
        temp_blks_read DESC
    LIMIT 100) a
UNION
SELECT
    *
FROM (
    SELECT
        *
    FROM
        q_data
    WHERE
        temp_blks_written > 0
    ORDER BY
        temp_blks_written DESC
    LIMIT 100) a) b;
