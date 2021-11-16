select distinct /* pgwatch2_generated */
    (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
    'partial_index_candidates'::text as tag_reco_topic,
    quote_ident(ni.nspname)||'.'||quote_ident(ci.relname) as tag_object_name,
    ('index ' || quote_ident(ni.nspname)||'.'||quote_ident(ci.relname) || ' on ' || quote_ident(s.schemaname) || '.' || quote_ident(s.tablename) || ' column ' || quote_ident(s.attname)  || ' could possibly be declared partial leaving out NULL-s')::text as recommendation,
    'NULL fraction: ' || round((null_frac * 100)::numeric, 1) || '%, rowcount estimate: ' || (c.reltuples)::int8 || ', current definition: ' ||  pg_get_indexdef(i.indexrelid) as extra_info
from
    pg_stats s
    join pg_attribute a using (attname)
    join pg_index i on i.indkey[0] = a.attnum and i.indrelid = a.attrelid
    join pg_class c on c.oid = i.indrelid
    join pg_class ci on ci.oid = i.indexrelid
    join pg_namespace ni on ni.oid = ci.relnamespace
where
  not indisprimary
  and not indisunique
  and indisready
  and indisvalid
  and i.indnatts = 1 /* simple 1 column indexes */
  and null_frac > 0.5 /* 50% empty */
  and not pg_get_indexdef(i.indexrelid) like '% WHERE %'
  and c.reltuples >= 1e5 /* ignore smaller tables */
  and not exists ( /* leave out sub-partitions */
      select * from pg_inherits where inhrelid = c.oid
    )
;
