select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  quote_ident(schemaname) as tag_schema,
  quote_ident(relname) as tag_table_name,
  quote_ident(schemaname)||'.'||quote_ident(relname) as tag_table_full_name,
  pg_relation_size(relid) as table_size_b,
  pg_total_relation_size(relid) as total_relation_size_b,
  pg_relation_size((select reltoastrelid from pg_class where oid = ut.relid)) as toast_size_b,
  extract(epoch from now() - greatest(last_vacuum, last_autovacuum)) as seconds_since_last_vacuum,
  extract(epoch from now() - greatest(last_analyze, last_autoanalyze)) as seconds_since_last_analyze,
  seq_scan,
  seq_tup_read,
  idx_scan,
  idx_tup_fetch,
  n_tup_ins,
  n_tup_upd,
  n_tup_del,
  n_tup_hot_upd,
  vacuum_count,
  autovacuum_count,
  analyze_count,
  autoanalyze_count
from
  pg_stat_user_tables ut
where
  -- leaving out fully locked tables as pg_relation_size also wants a lock and would wait
  not exists (select 1 from pg_locks where relation = relid and mode = 'AccessExclusiveLock' and granted);
