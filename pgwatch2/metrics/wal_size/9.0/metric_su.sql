select /* pgwatch2_generated */
    (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
    sum((pg_stat_file('pg_xlog/'||f)).size)::int8 as wal_size_b from (select pg_ls_dir('pg_xlog') f) ls
;
