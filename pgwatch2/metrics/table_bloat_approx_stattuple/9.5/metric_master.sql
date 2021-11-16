/* NB! accessing pgstattuple_approx directly requires superuser or pg_stat_scan_tables/pg_monitor builtin roles */
select /* pgwatch2_generated */
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  quote_ident(n.nspname)||'.'||quote_ident(c.relname) as tag_full_table_name,
  approx_free_percent,
  approx_free_space as approx_free_space_b,
  approx_tuple_count,
  dead_tuple_percent,
  dead_tuple_len as dead_tuple_len_b
from
  pg_class c
  join lateral pgstattuple_approx(c.oid) st on (c.oid not in (select relation from pg_locks where mode = 'AccessExclusiveLock'))  -- skip locked tables,
  join pg_namespace n on n.oid = c.relnamespace
where
  relkind in ('r', 'm')
  and c.relpages >= 128 -- tables > 1mb
  and not n.nspname like any (array[E'pg\\_%', 'information_schema']);
