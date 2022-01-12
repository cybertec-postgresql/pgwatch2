select /* pgwatch2_generated */
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  schemaname::text AS tag_schema,
  funcname::text  AS tag_function_name,
  quote_ident(schemaname)||'.'||quote_ident(funcname) as tag_function_full_name,
  p.oid::text as tag_oid, -- for overloaded funcs
  calls as sp_calls,
  self_time,
  total_time
FROM
  pg_stat_user_functions f
  JOIN
  pg_proc p ON p.oid = f.funcid
ORDER BY
  total_time DESC
LIMIT
  300;
