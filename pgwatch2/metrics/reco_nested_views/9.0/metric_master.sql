WITH RECURSIVE views AS (
   -- get the directly depending views
   SELECT v.oid::regclass AS view,
          format('%s.%s', quote_ident(n.nspname), quote_ident(v.relname)) as full_name,
          1 AS level
   FROM pg_depend AS d
      JOIN pg_rewrite AS r
         ON r.oid = d.objid
      JOIN pg_class AS v
         ON v.oid = r.ev_class
      JOIN pg_namespace AS n
         ON n.oid = v.relnamespace
   WHERE v.relkind = 'v'
     AND NOT n.nspname = ANY(array['information_schema', E'pg\\_%'])
     AND NOT v.relname LIKE E'pg\\_%'
     AND d.classid = 'pg_rewrite'::regclass
     AND d.refclassid = 'pg_class'::regclass
     AND d.deptype = 'n'
UNION ALL
   -- add the views that depend on these
   SELECT v.oid::regclass,
          format('%s.%s', quote_ident(n.nspname), quote_ident(v.relname)) as full_name,
          views.level + 1
   FROM views
      JOIN pg_depend AS d
         ON d.refobjid = views.view
      JOIN pg_rewrite AS r
         ON r.oid = d.objid
      JOIN pg_class AS v
         ON v.oid = r.ev_class
      JOIN pg_namespace AS n
         ON n.oid = v.relnamespace
   WHERE v.relkind = 'v'
     AND NOT n.nspname = ANY(array['information_schema', E'pg\\_%'])
     AND d.classid = 'pg_rewrite'::regclass
     AND d.refclassid = 'pg_class'::regclass
     AND d.deptype = 'n'
     AND v.oid <> views.view  -- avoid loop
)
SELECT
  'overly_nested_views'::text AS tag_reco_topic,
  full_name as tag_object_name,
  'overly nested views can affect performance' recommendation,
  'nesting_depth: ' || max(level) AS extra_info
FROM views
GROUP BY 1, 2
HAVING max(level) > 5
ORDER BY max(level) DESC;
