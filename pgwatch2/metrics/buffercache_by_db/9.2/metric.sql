select /* pgwatch2_generated */
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  datname as tag_database,
  count(*) * (current_setting('block_size')::int8) as size_b
FROM
  pg_buffercache AS b,
  pg_database AS d
WHERE
  d.oid = b.reldatabase
GROUP BY
  datname;
