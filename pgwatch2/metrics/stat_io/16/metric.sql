 SELECT /* pgwatch2_generated */
    (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
    coalesce(backend_type, 'total') as tag_backend_type,
    sum(coalesce(reads, 0))::int8  as reads,
    (sum(coalesce(reads, 0) * op_bytes) / 1e6)::int8 as read_bytes_mb,
    sum(coalesce(read_time, 0))::int8 as read_time_ms,
    sum(coalesce(writes, 0))::int8 as writes,
    (sum(coalesce(writes, 0) * op_bytes) / 1e6)::int8 as write_bytes_mb,
    sum(coalesce(write_time, 0))::int8 as write_time_ms,
    sum(coalesce(writebacks, 0))::int8 as writebacks,
    (sum(coalesce(writebacks, 0) * op_bytes) / 1e6)::int8 as writeback_bytes_mb,
    sum(coalesce(writeback_time, 0))::int8 as writeback_time_ms,
    sum(coalesce(fsyncs, 0))::int8 fsyncs,
    sum(coalesce(fsync_time, 0))::int8 fsync_time_ms,
    max(extract(epoch from now() - stats_reset)::int) as stats_reset_s
FROM
    pg_stat_io
GROUP BY
   ROLLUP (backend_type);
