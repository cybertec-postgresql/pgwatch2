select /* pgwatch2_generated */
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  *
from (
  select
    format('%I.%I', sui.schemaname, sui.indexrelname) as tag_index_full_name,
    sui.idx_scan,
    coalesce(pg_relation_size(sui.indexrelid), 0) as index_size_b,
    system_identifier::text as tag_sys_id /* to easily check also all replicas as could be still used there */
  from
    pg_stat_user_indexes sui
    join pg_index i on i.indexrelid = sui.indexrelid
    join pg_control_system() on true
  where not sui.schemaname like E'pg\\_temp%'
  and idx_scan = 0
  and not (indisprimary or indisunique or indisexclusion)
  and not exists (select * from pg_locks where relation = sui.relid and mode = 'AccessExclusiveLock')
) x
where index_size_b > 100*1024^2 /* list >100MB only */
order by index_size_b desc
limit 25;
