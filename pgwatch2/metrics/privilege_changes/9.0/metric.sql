select
  'table'::text as object_type,
  grantee::text as tag_role,
  quote_ident(table_schema) || '.' || quote_ident(table_name) as tag_object,
  privilege_type
from
  information_schema.table_privileges /* includes also VIEW-s actually */
where
  not grantee = any (select rolname from pg_roles where rolsuper or oid < 16384)
  and not table_schema in ('information_schema', 'pg_catalog')

union all

select
  /* quite a heavy query, maybe faster directly via pg_attribute + has_column_privilege? */
  'column' as object_type,
  grantee::text as tag_role,
  quote_ident(table_schema) || '.' || quote_ident(table_name) as tag_object,
  privilege_type
from
  information_schema.column_privileges cp
where
  not table_schema in ('pg_catalog', 'information_schema')
  and not grantee = any (select rolname from pg_roles where rolsuper or oid < 16384)
  and not exists (
        select * from information_schema.table_privileges
        where table_schema = cp.table_schema
        and table_name = cp.table_name
        and grantee = cp.grantee
        and privilege_type = cp.privilege_type
)

union all

select
  'function' as object_type,
  grantee::text as tag_role,
  quote_ident(routine_schema) || '.' || quote_ident(routine_name) as tag_object,
  privilege_type
from
  information_schema.routine_privileges
where
  not routine_schema in ('information_schema', 'pg_catalog')
  and not grantee = any (select rolname from pg_roles where rolsuper or oid < 16384)

union all

SELECT 'schema' AS object_type,
       r.rolname::text as tag_role,
       quote_ident(n.nspname) as tag_object,
       p.perm as privilege_type
FROM pg_catalog.pg_namespace AS n
   CROSS JOIN pg_catalog.pg_roles AS r
   CROSS JOIN (VALUES ('USAGE'), ('CREATE')) AS p(perm)
WHERE NOT n.nspname IN ('information_schema', 'pg_catalog')
  AND n.nspname NOT LIKE 'pg_%'
  AND NOT r.rolsuper
  AND r.oid >= 16384
  AND has_schema_privilege(r.oid, n.oid, p.perm)

union all

SELECT 'database' AS object_type,
    r.rolname::text AS role_name,
    quote_ident(datname) as tag_object,
    p.perm AS permission
FROM pg_catalog.pg_database AS d
   CROSS JOIN pg_catalog.pg_roles AS r
   CROSS JOIN (VALUES ('CREATE'), ('CONNECT'), ('TEMPORARY')) AS p(perm)
WHERE d.datname = current_database()
  AND NOT r.rolsuper
  AND r.oid >= 16384
  AND has_database_privilege(r.oid, d.oid, p.perm)
;
