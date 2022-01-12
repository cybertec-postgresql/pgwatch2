select /* pgwatch2_generated */
    (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
    r, b, swpd, free, buff, cache, si, so, bi, bo, "in", cs, us, sy, id, wa, st, cpu_count, load_1m, load_5m, load_15m, total_memory
from
    get_vmstat();

