with q_data as (
  select /* pgwatch2_generated */
    (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
    '-' as tag_query,
    coalesce(queryid::text, 'insufficient-privileges-total') as tag_queryid,
    array_to_string(array_agg(distinct quote_ident(pg_get_userbyid(userid))), ',') as users,
    sum(s.calls)::int8 as calls,
    round(sum(s.total_exec_time)::numeric, 3)::double precision as total_time,
    sum(shared_blks_hit)::int8 as shared_blks_hit,
    sum(shared_blks_read)::int8 as shared_blks_read,
    sum(shared_blks_written)::int8 as shared_blks_written,
    sum(shared_blks_dirtied)::int8 as shared_blks_dirtied,
    sum(temp_blks_read)::int8 as temp_blks_read,
    sum(temp_blks_written)::int8 as temp_blks_written,
    round(sum(blk_read_time)::numeric, 3)::double precision as blk_read_time,
    round(sum(blk_write_time)::numeric, 3)::double precision as blk_write_time,
    sum(wal_fpi) as wal_fpi,
    sum(wal_bytes) as wal_bytes,
    round(sum(s.total_plan_time)::numeric, 3)::double precision as total_plan_time
  from
    pg_stat_statements s
  where
    calls > 5
    and total_exec_time > 0
    and dbid = (select oid from pg_database where datname = current_database())
    and not upper(s.query) like any (array['DEALLOCATE%', 'SET %', 'RESET %', 'BEGIN%', 'BEGIN;',
      'COMMIT%', 'END%', 'ROLLBACK%', 'SHOW%'])
  group by
    queryid
)
select * from (
  select
    *
  from
    q_data
  where
    total_time > 0
  order by
    total_time desc
  limit 100
) a
union
select * from (
  select
    *
  from
    q_data
  order by
    calls desc
  limit 100
) a
union
select * from (
  select
    *
  from
    q_data
  where
    shared_blks_read > 0
  order by
    shared_blks_read desc
  limit 100
) a
union
select * from (
  select
    *
  from
    q_data
  where
    shared_blks_written > 0
  order by
    shared_blks_written desc
  limit 100
) a
union
select * from (
  select
    *
  from
    q_data
  where
    temp_blks_read > 0
  order by
    temp_blks_read desc
  limit 100
) a
union
select * from (
  select
    *
  from
    q_data
  where
    temp_blks_written > 0
  order by
    temp_blks_written desc
  limit 100
) a;
