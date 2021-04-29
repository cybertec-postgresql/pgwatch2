WITH q_locked_rels AS (
  select relation from pg_locks where mode = 'AccessExclusiveLock' and granted
)
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
  md5(regexp_replace(regexp_replace(pg_get_indexdef(sui.indexrelid),indexrelname,'X'), '^CREATE UNIQUE','CREATE')) as tag_index_def_hash,
  regexp_replace(regexp_replace(pg_get_indexdef(sui.indexrelid),indexrelname,'X'), '^CREATE UNIQUE','CREATE') as index_def,
  case when not i.indisvalid then 1 else 0 end as is_invalid_int,
  case when i.indisprimary then 1 else 0 end as is_pk_int,
  case when i.indisunique or indisexclusion then 1 else 0 end as is_uq_or_exc,
  system_identifier::text as tag_sys_id
FROM
  pg_stat_user_indexes sui
  JOIN
  pg_index i USING (indexrelid)
  JOIN
  pg_control_system() ON true
WHERE
  relid IN (select *
            from (select relid
                  from pg_stat_user_tables
                  where not schemaname like any (array [E'pg\\_temp%', E'\\_timescaledb%'])
                  order by pg_table_size(relid) desc nulls last
                  limit 100
                 ) x
            union
            select *
            from (
                     select relid
                     from pg_stat_user_tables
                     where not schemaname like any (array [E'pg\\_temp%', E'\\_timescaledb%'])
                     order by coalesce(n_tup_ins, 0) + coalesce(n_tup_upd, 0) + coalesce(n_tup_del, 0) desc
                     limit 100) y
            union
            select *
            from (
                     select relid
                     from pg_stat_user_tables
                     where not schemaname like any (array [E'pg\\_temp%', E'\\_timescaledb%'])
                     and idx_scan > 1
                     order by idx_scan desc
                     limit 100) z
            union
            select *
            from (
                     select relid
                     from pg_stat_user_indexes
                     where not schemaname like any (array [E'pg\\_temp%', E'\\_timescaledb%'])
                     order by pg_relation_size(indexrelid) desc nulls last
                     limit 100) w
  )
  AND NOT schemaname like any(array[E'pg\\_temp%', E'\\_timescaledb%'])
  AND i.indrelid not in (select relation from q_locked_rels)
  AND i.indexrelid not in (select relation from q_locked_rels)
ORDER BY
  schemaname, relname, indexrelname;
