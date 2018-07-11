SELECT
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  datname,
  count(*) * 8192
FROM
  pg_buffercache AS b,
  pg_database AS d
WHERE
  d.oid = b.reldatabase
GROUP BY
  datname;
