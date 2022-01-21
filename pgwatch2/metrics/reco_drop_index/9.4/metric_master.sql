/* assumes the pg_qualstats extension */
with q_database_size as (
  select pg_database_size(current_database()) as database_size_b
)
select /* pgwatch2_generated */
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  'drop_index'::text as tag_reco_topic,
  quote_ident(schemaname)||'.'||quote_ident(indexrelname) as tag_object_name,
  ('DROP INDEX ' || quote_ident(schemaname)||'.'||quote_ident(indexrelname) || ';')::text as recommendation,
  'NB! Make sure to also check replica pg_stat_user_indexes.idx_scan count if using them for queries'::text as extra_info
from
  pg_stat_user_indexes
  join
  pg_index using (indexrelid)
  join
  q_database_size on true
where
  idx_scan = 0
  and ((pg_relation_size(indexrelid)::numeric / database_size_b) > 0.005 /* 0.5% DB size threshold */
    or indisvalid)
  and not indisprimary
  and not indisreplident
  and not schemaname like '_timescaledb%'
;
