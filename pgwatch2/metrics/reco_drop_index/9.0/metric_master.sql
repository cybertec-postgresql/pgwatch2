/* assumes the pg_qualstats extension */
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  'drop_index'::text as tag_reco_topic,
  quote_ident(schemaname)||'.'||quote_ident(indexrelname) as tag_object_name,
  ('DROP INDEX ' || quote_ident(schemaname)||'.'||quote_ident(indexrelname) || ';')::text as recommendation,
  'NB! Before dropping make sure to also check replica pg_stat_user_indexes.idx_scan count if using them for queries'::text as extra_info
from
  pg_stat_user_indexes
  join
  pg_index using (indexrelid)
where
  idx_scan = 0
  and ((pg_relation_size(indexrelid)::numeric / (pg_database_size(current_database()))) > 0.005 /* 0.5% DB size threshold */
    or indisvalid)
  and not indisprimary
;
