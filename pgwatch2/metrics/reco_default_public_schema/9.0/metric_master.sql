select
  'default_public_schema_privs' as tag_reco_topic,
  nspname::text as tag_object_name,
  'REVOKE CREATE ON SCHEMA public FROM PUBLIC;' as recommendation,
  'only authorized users should be allowed to create new objects' as extra_info
from
  pg_namespace
where
  nspname = 'public'
  and nspacl::text ~ E'[,\\{]+=U?C/'
;