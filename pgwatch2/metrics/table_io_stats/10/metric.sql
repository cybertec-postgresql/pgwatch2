select * from (
                  with recursive
                      q_root_part as (
                            select c.oid,
                                   c.relkind,
                                   n.nspname root_schema,
                                   c.relname root_relname
                            from pg_class c
                                     join pg_namespace n on n.oid = c.relnamespace
                            where relkind in ('p', 'r')
                              and relpersistence != 't'
                              and not n.nspname like any (array[E'pg\\_%', 'information_schema', E'\\_timescaledb%'])
                              and not exists(select * from pg_inherits where inhrelid = c.oid)
                              and exists(select * from pg_inherits where inhparent = c.oid)
                      ),
                      q_parts (relid, relkind, level, root) as (
                          select oid, relkind, 1, oid
                          from q_root_part
                          union all
                          select inhrelid, c.relkind, level + 1, q.root
                          from pg_inherits i
                                   join q_parts q on inhparent = q.relid
                                   join pg_class c on c.oid = i.inhrelid
                      ),
                      q_tstats as (
                          SELECT (extract(epoch from now()) * 1e9)::int8                as epoch_ns,
                                 relid,
                                 schemaname::text                                       as tag_schema,
                                 relname::text                                          as tag_table_name,
                                 quote_ident(schemaname) || '.' || quote_ident(relname) as tag_table_full_name,
                                 heap_blks_read,
                                 heap_blks_hit,
                                 idx_blks_read,
                                 idx_blks_hit,
                                 toast_blks_read,
                                 toast_blks_hit,
                                 tidx_blks_read,
                                 tidx_blks_hit
                          FROM pg_statio_user_tables
                          WHERE NOT schemaname LIKE E'pg\\_temp%'
                            AND (heap_blks_read > 0 OR heap_blks_hit > 0 OR idx_blks_read > 0 OR idx_blks_hit > 0 OR
                                 tidx_blks_read > 0 OR
                                 tidx_blks_hit > 0)
                      )
                  select epoch_ns,
                         tag_schema,
                         tag_table_name,
                         tag_table_full_name,
                         0 as is_part_root,
                         heap_blks_read,
                         heap_blks_hit,
                         idx_blks_read,
                         idx_blks_hit,
                         toast_blks_read,
                         toast_blks_hit,
                         tidx_blks_read,
                         tidx_blks_hit
                  from q_tstats
                  where not tag_schema like E'\\_timescaledb%'
                  and not exists (select * from q_root_part where oid = q_tstats.relid)

                  union all

                  select *
                  from (
                           select epoch_ns,
                                  quote_ident(qr.root_schema)                                        as tag_schema,
                                  quote_ident(qr.root_relname)                                       as tag_table_name,
                                  quote_ident(qr.root_schema) || '.' || quote_ident(qr.root_relname) as tag_table_full_name,
                                  1                                                                  as is_part_root,
                                  sum(heap_blks_read)::int8,
                                  sum(heap_blks_hit)::int8,
                                  sum(idx_blks_read)::int8,
                                  sum(idx_blks_hit)::int8,
                                  sum(toast_blks_read)::int8,
                                  sum(toast_blks_hit)::int8,
                                  sum(tidx_blks_read)::int8,
                                  sum(tidx_blks_hit)::int8
                           from q_tstats ts
                                    join q_parts qp on qp.relid = ts.relid
                                    join q_root_part qr on qr.oid = qp.root
                           group by 1, 2, 3, 4
                       ) x
              ) y
order by
  coalesce(heap_blks_read, 0) +
  coalesce(heap_blks_hit, 0) +
  coalesce(idx_blks_read, 0) +
  coalesce(idx_blks_hit, 0) +
  coalesce(toast_blks_read, 0) +
  coalesce(toast_blks_hit, 0) +
  coalesce(tidx_blks_read, 0) +
  coalesce(tidx_blks_hit, 0)
  desc limit 300;
