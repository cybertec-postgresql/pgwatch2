select /* pgwatch2_generated */
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  pg_database_size(current_database()) as size_b,
  (select sum(pg_total_relation_size(c.oid))::int8
   from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where nspname = 'pg_catalog' and relkind = 'r'
  ) as catalog_size_b;
