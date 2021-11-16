/* assumes the pg_qualstats extension and superuser or select grants on pg_qualstats_indexes_ddl view */
select /* pgwatch2_generated */
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  'create_index'::text as tag_reco_topic,
  quote_ident(nspname::text)||'.'||quote_ident(relid::text) as tag_object_name,
  ddl as recommendation,
  ('qual execution count: '|| execution_count)::text as extra_info
from
  pg_qualstats_indexes_ddl
order by
  execution_count desc
limit 25;
