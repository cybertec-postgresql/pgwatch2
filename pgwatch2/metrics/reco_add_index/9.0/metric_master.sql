/* assumes the pg_qualstats extension */
select
  'create_index' as tag_reco_topic,
  quote_ident(nspname::text)||'.'||quote_ident(relid::text) as tag_object_name,
  ddl as recommendation,
  'qual execution count: '|| execution_count as extra_info
from
  pg_qualstats_indexes_ddl;
