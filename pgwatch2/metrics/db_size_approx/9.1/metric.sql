select /* pgwatch2_generated */
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  current_setting('block_size')::int8 * (
    select sum(relpages) from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where c.relpersistence != 't'
  ) as size_b,
  current_setting('block_size')::int8 * (
    select sum(c.relpages + coalesce(ct.relpages, 0) + coalesce(cti.relpages, 0))
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    left join pg_class ct on ct.oid = c.reltoastrelid
    left join pg_index ti on ti.indrelid = ct.oid
    left join pg_class cti on cti.oid = ti.indexrelid
    where nspname = 'pg_catalog'
    and (c.relkind = 'r'
      or c.relkind = 'i' and not c.relname ~ '^pg_toast')
  ) as catalog_size_b;
