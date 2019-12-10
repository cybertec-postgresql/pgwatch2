with q_sprocs as (
select
  format('%s.%s', quote_ident(nspname), quote_ident(proname)) as sproc_name,
  'alter function ' || proname || '(' || pg_get_function_arguments(p.oid) || ') set search_path = X;' as fix_sql
from
  pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where prosecdef and not 'search_path' = ANY(coalesce(proconfig, '{}'::text[]))
)
select
  'sprocs_wo_search_path' as tag_reco_topic,
  sproc_name as tag_object_name,
  'functions without fixed search_path can be potentially abused by malicious users if used objects are not fully qualified' as recommendation,
  'to fix: ' || fix_sql as extra_info
from
  q_sprocs
order by
   tag_object_name, extra_info;
