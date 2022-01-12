WITH q_locks AS (
  select
    *
  from
    pg_locks
  where
    pid != pg_backend_pid()
    and database = (select oid from pg_database where datname = current_database())
)
select /* pgwatch2_generated */
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  locktypes AS tag_locktype,
  coalesce((select count(*) FROM q_locks WHERE locktype = locktypes), 0) AS count
FROM
  unnest('{relation, extend, page, tuple, transactionid, virtualxid, object, userlock, advisory}'::text[]) locktypes;
