select /* pgwatch2_generated */
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  quote_ident(schemaname) as tag_schema,
  quote_ident(ut.relname) as tag_table_name,
  quote_ident(schemaname)||'.'||quote_ident(ut.relname) as tag_table_full_name,
  pg_table_size(relid) as table_size_b,
  abs(greatest(ceil(log((pg_table_size(relid)+1) / 10^6)), 0))::text as tag_table_size_cardinality_mb, -- i.e. 0=<1MB, 1=<10MB, 2=<100MB,..
  pg_total_relation_size(relid) as total_relation_size_b,
  case when reltoastrelid != 0 then pg_total_relation_size(reltoastrelid) else 0::int8 end as toast_size_b,
  (extract(epoch from now() - greatest(last_vacuum, last_autovacuum)))::int8 as seconds_since_last_vacuum,
  (extract(epoch from now() - greatest(last_analyze, last_autoanalyze)))::int8 as seconds_since_last_analyze,
  case when 'autovacuum_enabled=off' = ANY(c.reloptions) then 1 else 0 end as no_autovacuum,
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
  age(relfrozenxid) as tx_freeze_age,
  relpersistence
from
  pg_stat_user_tables ut
  join
  pg_class c on c.oid = ut.relid
where
  -- leaving out fully locked tables as pg_relation_size also wants a lock and would wait
  not exists (select 1 from pg_locks where relation = relid and mode = 'AccessExclusiveLock')
  and c.relpersistence != 't' -- and temp tables
order by table_size_b desc nulls last limit 300;
