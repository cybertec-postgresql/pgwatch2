select /* pgwatch2_generated */
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  quote_ident(nspname)||'.'||quote_ident(c.relname) as tag_index,
  quote_ident(nspname)||'.'||quote_ident(r.relname) as "table",
  i.indisvalid::text as is_valid,
  coalesce(md5(pg_get_indexdef(i.indexrelid)), random()::text) as md5
from
  pg_index i
  join
  pg_class c on c.oid = i.indexrelid
  join
  pg_class r on r.oid = i.indrelid
  join
  pg_namespace n on n.oid = c.relnamespace
where
  c.relnamespace not in (select oid from pg_namespace where nspname like any(array[E'pg\\_%', 'information_schema']));
