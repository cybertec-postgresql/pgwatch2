select /* pgwatch2_generated */
    (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
    wal_records,
    wal_fpi,
    (wal_bytes / 1024)::int8 as wal_bytes_kb,
    wal_buffers_full,
    wal_write,
    wal_sync,
    wal_write_time::int8,
    wal_sync_time::int8
from
    pg_stat_wal;
