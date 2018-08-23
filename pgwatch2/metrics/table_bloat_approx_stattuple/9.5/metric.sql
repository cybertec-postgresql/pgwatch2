select
  quote_ident(n.nspname)||'.'||quote_ident(c.relname) as tag_full_table_name,
  approx_free_percent,
  approx_free_space,
  approx_tuple_count
from
  pg_class c
  join lateral public.pgstattuple_approx(c.oid) st on (c.oid not in (select relation from pg_locks where mode = 'AccessExclusiveLock'))  -- skip locked tables,
  join pg_namespace n on n.oid = c.relnamespace
where
  relkind in ('r', 'm')
  and c.relpages >= 128 -- tables > 1mb
  and not n.nspname like any (array[E'pg\\_%', 'information_schema']);
