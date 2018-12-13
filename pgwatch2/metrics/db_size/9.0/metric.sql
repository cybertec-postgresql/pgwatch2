select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  pg_database_size(current_database()) as size_b;
