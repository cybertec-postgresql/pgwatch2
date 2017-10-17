UPDATE pgwatch2.metric
SET m_sql =
  $sql$
with q_data as (
  select
    (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
    queryid::text as tag_queryid,
    max(ltrim(regexp_replace(query, E'[ \\t\\n\\r]+' , ' ', 'g')))::varchar(65000) as tag_query,
    sum(s.calls)::int8 as calls,
    sum(s.total_time)::double precision as total_time,
    sum(shared_blks_hit)::int8 as shared_blks_hit,
    sum(shared_blks_read)::int8 as shared_blks_read,
    sum(shared_blks_written)::int8 as shared_blks_written,
    sum(temp_blks_read)::int8 as temp_blks_read,
    sum(temp_blks_written)::int8 as temp_blks_written,
    sum(blk_read_time)::double precision as blk_read_time,
    sum(blk_write_time)::double precision as blk_write_time
  from
    public.get_stat_statements() s
  where
    calls > 5
    and total_time > 0
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
$sql$
WHERE
  m_name = 'stat_statements'
  AND m_pg_version_from = 9.2
;
