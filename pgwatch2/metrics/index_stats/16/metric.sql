/* NB! does not return all index stats but biggest, top scanned and biggest unused ones */
WITH q_locked_rels AS ( /* pgwatch2_generated */
  select relation from pg_locks where mode = 'AccessExclusiveLock'
),
q_index_details AS (
  select
    sui.schemaname,
    sui.indexrelname,
    sui.relname,
    sui.indexrelid,
    coalesce(pg_relation_size(sui.indexrelid), 0) as index_size_b,
    sui.idx_scan,
    sui.idx_tup_read,
    sui.idx_tup_fetch,
    io.idx_blks_read,
    io.idx_blks_hit,
    i.indisvalid,
    i.indisprimary,
    i.indisunique,
    i.indisexclusion,
    extract(epoch from now() - last_idx_scan)::int as last_idx_scan_s
  from
    pg_stat_user_indexes sui
    join pg_statio_user_indexes io on io.indexrelid = sui.indexrelid
    join pg_index i on i.indexrelid = sui.indexrelid
  where not sui.schemaname like any (array [E'pg\\_temp%', E'\\_timescaledb%'])
  and not exists (select * from q_locked_rels where relation = sui.relid or relation = sui.indexrelid)
),
q_top_indexes AS (
    /* biggest */
    select *
    from (
             select indexrelid
             from q_index_details
             where idx_scan > 1
             order by index_size_b desc
             limit 200
         ) x
    union
    /* most block traffic */
    select *
    from (
             select indexrelid
             from q_index_details
             order by coalesce(idx_blks_read, 0) + coalesce(idx_blks_hit, 0) desc
             limit 200
         ) y
    union
    /* most scans */
    select *
    from (
             select indexrelid
             from q_index_details
             order by idx_scan desc nulls last
             limit 200
         ) z
    union
    /* biggest unused non-constraint */
    select *
    from (
             select q.indexrelid
             from q_index_details q
             where idx_scan = 0
             and not (indisprimary or indisunique or indisexclusion)
             order by index_size_b desc
             limit 200
         ) z
    union
    /* all invalid */
    select *
    from (
             select q.indexrelid
             from q_index_details q
             where not indisvalid
         ) zz
)
select /* pgwatch2_generated */
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  schemaname::text as tag_schema,
  indexrelname::text as tag_index_name,
  quote_ident(schemaname)||'.'||quote_ident(indexrelname) as tag_index_full_name,
  relname::text as tag_table_name,
  quote_ident(schemaname)||'.'||quote_ident(relname) as tag_table_full_name,
  coalesce(idx_scan, 0) as idx_scan,
  coalesce(idx_tup_read, 0) as idx_tup_read,
  coalesce(idx_tup_fetch, 0) as idx_tup_fetch,
  coalesce(index_size_b, 0) as index_size_b,
  quote_ident(schemaname)||'.'||quote_ident(indexrelname) as index_full_name_val,
  md5(regexp_replace(regexp_replace(pg_get_indexdef(indexrelid),indexrelname,'X'), '^CREATE UNIQUE','CREATE')) as tag_index_def_hash,
  regexp_replace(regexp_replace(pg_get_indexdef(indexrelid),indexrelname,'X'), '^CREATE UNIQUE','CREATE') as index_def,
  case when not indisvalid then 1 else 0 end as is_invalid_int,
  case when indisprimary then 1 else 0 end as is_pk_int,
  case when indisunique or indisexclusion then 1 else 0 end as is_uq_or_exc,
  system_identifier::text as tag_sys_id,
  last_idx_scan_s
FROM
  q_index_details id
  JOIN
  pg_control_system() ON true
WHERE
  indexrelid IN (select indexrelid from q_top_indexes)
ORDER BY
  id.schemaname, id.relname, id.indexrelname;
