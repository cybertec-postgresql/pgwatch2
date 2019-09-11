select
    (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
    (sum((pg_stat_file('pg_wal/' || name)).size))::int8 as wal_size_b
from pg_ls_waldir();
