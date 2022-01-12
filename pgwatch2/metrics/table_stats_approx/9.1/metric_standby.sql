with q_tbls_by_total_associated_relpages_approx as (
  select * from (
    select
      c.oid,
      c.relname,
      c.relpages,
      coalesce((select sum(relpages) from pg_class ci join pg_index i on i.indexrelid = ci.oid where i.indrelid = c.oid), 0) as index_relpages,
      coalesce((select coalesce(ct.relpages, 0) + coalesce(cti.relpages, 0) from pg_class ct left join pg_index ti on ti.indrelid = ct.oid left join pg_class cti on cti.oid = ti.indexrelid where ct.oid = c.reltoastrelid), 0) as toast_relpages,
      case when 'autovacuum_enabled=off' = ANY(c.reloptions) then 1 else 0 end as no_autovacuum,
      c.relpersistence
    from
      pg_class c
      join pg_namespace n on n.oid = c.relnamespace
    where
      not n.nspname like any (array[E'pg\\_%', 'information_schema'])
      and c.relkind = 'r'
      and c.relpersistence != 't'
  ) x
  order by relpages + index_relpages + toast_relpages desc limit 300
), q_block_size as (
  select current_setting('block_size')::int8 as bs
)
select /* pgwatch2_generated */
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  quote_ident(schemaname)||'.'||quote_ident(ut.relname) as tag_table_full_name,
  bs * relpages as table_size_b,
  abs(greatest(ceil(log((bs*relpages+1) / 10^6)), 0))::text as tag_table_size_cardinality_mb, -- i.e. 0=<1MB, 1=<10MB, 2=<100MB,..
  bs * (relpages + index_relpages + toast_relpages) as total_relation_size_b,
  bs * toast_relpages as toast_size_b,
  (extract(epoch from now() - greatest(last_vacuum, last_autovacuum)))::int8 as seconds_since_last_vacuum,
  (extract(epoch from now() - greatest(last_analyze, last_autoanalyze)))::int8 as seconds_since_last_analyze,
  no_autovacuum,
  seq_scan,
  seq_tup_read,
  coalesce(idx_scan, 0) as idx_scan,
  coalesce(idx_tup_fetch, 0) as idx_tup_fetch,
  n_tup_ins,
  n_tup_upd,
  n_tup_del,
  n_tup_hot_upd,
  n_live_tup,
  n_dead_tup,
  vacuum_count,
  autovacuum_count,
  analyze_count,
  autoanalyze_count,
  relpersistence
from
  pg_stat_user_tables ut
  join q_tbls_by_total_associated_relpages_approx t on t.oid = ut.relid
  join q_block_size on true
where
  -- leaving out fully locked tables as pg_relation_size also wants a lock and would wait
  not exists (select 1 from pg_locks where relation = relid and mode = 'AccessExclusiveLock');
