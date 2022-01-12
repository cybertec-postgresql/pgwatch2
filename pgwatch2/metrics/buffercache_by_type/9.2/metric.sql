select /* pgwatch2_generated */
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  CASE
    WHEN relkind = 'r' THEN 'Table'   -- TODO all relkinds covered?
    WHEN relkind = 'i' THEN 'Index'
    WHEN relkind = 't' THEN 'Toast'
    WHEN relkind = 'm' THEN 'Materialized view'
    ELSE 'Other'
  END as tag_relkind,
  count(*) * (current_setting('block_size')::int8) size_b
FROM
  pg_buffercache AS b,
  pg_class AS d
WHERE
  d.oid = b.relfilenode
GROUP BY
  relkind;
