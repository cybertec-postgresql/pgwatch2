select /* pgwatch2_generated */
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  format('%I.%I', n.nspname , ci.relname) as tag_index_full_name,
  coalesce(pg_relation_size(indexrelid), 0) as index_size_b
from
  pg_index i
  join pg_class ci on ci.oid = i.indexrelid
  join pg_class cr on cr.oid = i.indrelid
  join pg_namespace n on n.oid = ci.relnamespace
where not n.nspname like E'pg\\_temp%'
and not indisvalid
and not exists ( /* leave out ones that are being actively rebuilt */
  select * from pg_locks l
  join pg_stat_activity a using (pid)
  where l.relation = i.indexrelid
  and a.state = 'active'
  and a.query ~* 'concurrently'
)
and not exists (select * from pg_locks where relation = indexrelid and mode = 'AccessExclusiveLock') /* can't get size then */
order by index_size_b desc
limit 100;
