/* NB! accessing pgstattuple_approx directly requires superuser or pg_stat_scan_tables/pg_monitor builtin roles or
   execute grant on pgstattuple_approx(regclass)
*/
with table_bloat_approx as (
    select
        avg(approx_free_percent)::double precision as approx_free_percent,
        sum(approx_free_space)::double precision as approx_free_space,
        avg(dead_tuple_percent)::double precision as dead_tuple_percent,
        sum(dead_tuple_len)::double precision as dead_tuple_len
    from
        pg_class c
            join
        pg_namespace n on n.oid = c.relnamespace
            join lateral pgstattuple_approx(c.oid) on (c.oid not in (select relation from pg_locks where mode = 'AccessExclusiveLock'))  -- skip locked tables
    where
        relkind in ('r', 'm')
        and c.relpages >= 128 -- tables >1mb
        and not n.nspname != 'information_schema'
)
select /* pgwatch2_generated */
    (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
    approx_free_percent,
    approx_free_space as approx_free_space_b,
    dead_tuple_percent,
    dead_tuple_len as dead_tuple_len_b
from
    table_bloat_approx
where
     approx_free_space > 0;
