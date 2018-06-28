select
  c.relname,
  n.nspname,
  approx_free_percent,
  approx_free_space,
  approx_tuple_count
from
  pg_class c,
  public.pgstattuple_approx(c.oid) st,
  pg_namespace n
where
  relkind in ('r', 'm')
  and n.oid = c.relnamespace
  and c.relpages >= 128 -- tables > 1mb
  and not n.nspname like any (array[E'pg\\_%', 'information_schema'])
