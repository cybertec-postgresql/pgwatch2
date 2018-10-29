SELECT
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  schemaname::text as tag_schema,
  indexrelname::text as tag_index_name,
  quote_ident(schemaname)||'.'||quote_ident(indexrelname) as tag_index_full_name,
  relname::text as tag_table_name,
  quote_ident(schemaname)||'.'||quote_ident(relname) as tag_table_full_name,
  coalesce(idx_scan, 0) as idx_scan,
  coalesce(idx_tup_read, 0) as idx_tup_read,
  coalesce(idx_tup_fetch, 0) as idx_tup_fetch,
  coalesce(pg_relation_size(indexrelid), 0) as index_size_b,
  quote_ident(schemaname)||'.'||quote_ident(sui.indexrelname) as index_full_name_val,
  md5(regexp_replace(replace(pg_get_indexdef(sui.indexrelid),indexrelname,'X'), '^CREATE UNIQUE','CREATE')) as tag_index_def_hash,
  regexp_replace(replace(pg_get_indexdef(sui.indexrelid),indexrelname,'X'), '^CREATE UNIQUE','CREATE') as index_def,
  i.indisvalid as is_valid,
  i.indisprimary as is_pk
FROM
  pg_stat_user_indexes sui
  JOIN
  pg_index i USING (indexrelid)
WHERE
  NOT schemaname like E'pg\\_temp%'
ORDER BY
  schemaname, relname, indexrelname;
