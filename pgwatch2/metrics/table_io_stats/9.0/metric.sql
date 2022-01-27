select /* pgwatch2_generated */
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  schemaname::text as tag_schema,
  relname::text as tag_table_name,
  quote_ident(schemaname)||'.'||quote_ident(relname) as tag_table_full_name,
  heap_blks_read,
  heap_blks_hit,
  idx_blks_read,
  idx_blks_hit,
  toast_blks_read,
  toast_blks_hit,
  tidx_blks_read,
  tidx_blks_hit
FROM
  pg_statio_user_tables
WHERE
  NOT schemaname LIKE E'pg\\_temp%'
  AND (heap_blks_read > 0 OR heap_blks_hit > 0 OR idx_blks_read > 0 OR idx_blks_hit > 0 OR tidx_blks_read > 0 OR tidx_blks_hit > 0)
ORDER BY
  coalesce(heap_blks_read, 0) +
  coalesce(heap_blks_hit, 0) +
  coalesce(idx_blks_read, 0) +
  coalesce(idx_blks_hit, 0) +
  coalesce(toast_blks_read, 0) +
  coalesce(toast_blks_hit, 0) +
  coalesce(tidx_blks_read, 0) +
  coalesce(tidx_blks_hit, 0)
  DESC LIMIT 300;
