select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  pg_database_size(current_database()) as size_b,
  (select sum(pg_total_relation_size(oid)) from pg_class where relkind = 'r' and relname LIKE E'pg\\_%') as catalog_size_b;
