/* assumes the pg_qualstats extension */
select
  'drop_index' as tag_reco_topic,
  quote_ident(schemaname)||'.'||quote_ident(indexrelname) as tag_object_name,
  'DROP INDEX ' || quote_ident(schemaname)||'.'||quote_ident(indexrelname) || ';' as recommendation,
  'NB! Make sure to also check replica pg_stat_user_indexes.idx_scan count if using them for queries' as extra_info
from
  pg_stat_user_indexes
  join
  pg_index using (indexrelid)
where
  idx_scan = 0
  and ((pg_relation_size(indexrelid)::numeric / (pg_database_size(current_database()))) > 0.005 /* 0.5% DB size threshold */
    or indisvalid)
  and not indisprimary
  and not indisreplident
;
