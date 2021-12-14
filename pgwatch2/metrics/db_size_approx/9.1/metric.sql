select /* pgwatch2_generated */
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  current_setting('block_size')::int8 * (
    select sum(relpages) from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where c.relpersistence != 't'
  ) as size_b,
  current_setting('block_size')::int8 * (
    select sum(relpages)
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where nspname = 'pg_catalog'
  ) as catalog_size_b;
