with q_sprocs as (
select /* pgwatch2_generated */
  format('%s.%s', quote_ident(nspname), quote_ident(proname)) as sproc_name,
  'alter function ' || proname || '(' || pg_get_function_arguments(p.oid) || ') set search_path = X;' as fix_sql
from
  pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where prosecdef and not 'search_path' = ANY(coalesce(proconfig, '{}'::text[]))
  and not pg_catalog.obj_description(p.oid, 'pg_proc') ~ 'pgwatch2'
)
select /* pgwatch2_generated */
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  'sprocs_wo_search_path'::text as tag_reco_topic,
  sproc_name::text as tag_object_name,
  fix_sql::text as recommendation,
  'functions without fixed search_path can be potentially abused by malicious users if used objects are not fully qualified'::text as extra_info
from
  q_sprocs
order by
   tag_object_name, extra_info;
