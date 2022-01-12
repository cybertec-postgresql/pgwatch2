select /* pgwatch2_generated */
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  p.oid::text as tag_oid,
  quote_ident(nspname)||'.'||quote_ident(proname) as tag_sproc,
  md5(prosrc)
from
  pg_proc p
  join
  pg_namespace n on n.oid = pronamespace
where
  not nspname like any(array[E'pg\\_%', 'information_schema']);
