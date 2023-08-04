with recursive /* pgwatch2_generated */
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
        select (extract(epoch from now()) * 1e9)::int8                                                  as epoch_ns,
               relid, -- not sent to final output
               quote_ident(schemaname)                                                                  as tag_schema,
               quote_ident(ut.relname)                                                                  as tag_table_name,
               quote_ident(schemaname) || '.' || quote_ident(ut.relname)                                as tag_table_full_name,
               pg_table_size(relid)                                                                     as table_size_b,
               abs(greatest(ceil(log((pg_table_size(relid) + 1) / 10 ^ 6)), 0))::text                   as tag_table_size_cardinality_mb, -- i.e. 0=<1MB, 1=<10MB, 2=<100MB,..
               pg_total_relation_size(relid)                                                            as total_relation_size_b,
               case when c.reltoastrelid != 0 then pg_total_relation_size(c.reltoastrelid) else 0::int8 end as toast_size_b,
               (extract(epoch from now() - greatest(last_vacuum, last_autovacuum)))::int8               as seconds_since_last_vacuum,
               (extract(epoch from now() - greatest(last_analyze, last_autoanalyze)))::int8             as seconds_since_last_analyze,
               case when 'autovacuum_enabled=off' = ANY (c.reloptions) then 1 else 0 end                as no_autovacuum,
               seq_scan,
               seq_tup_read,
               coalesce(idx_scan, 0) as idx_scan,
               coalesce(idx_tup_fetch, 0) as idx_tup_fetch,
               n_tup_ins,
               n_tup_upd,
               n_tup_del,
               n_tup_hot_upd,
               n_live_tup,
               n_dead_tup,
               vacuum_count,
               autovacuum_count,
               analyze_count,
               autoanalyze_count,
               age(c.relfrozenxid) as tx_freeze_age,
               extract(epoch from now() - last_seq_scan)::int8 as last_seq_scan_s
        from pg_stat_user_tables ut
            join pg_class c on c.oid = ut.relid
            left join pg_class t on t.oid = c.reltoastrelid
            left join pg_index ti on ti.indrelid = t.oid
            left join pg_class tir on tir.oid = ti.indexrelid
        where
          -- leaving out fully locked tables as pg_relation_size also wants a lock and would wait
          not exists (select 1 from pg_locks where relation = relid and mode = 'AccessExclusiveLock')
          and c.relpersistence != 't' -- and temp tables
        order by case when c.relkind = 'p' then 1e9::int else coalesce(c.relpages, 0) + coalesce(t.relpages, 0) + coalesce(tir.relpages, 0) end desc
        limit 1500 /* NB! When changing the bottom final LIMIT also adjust this limit. Should be at least 5x bigger as approx sizes depend a lot on vacuum frequency.
                    The general idea is to reduce filesystem "stat"-ing on tables that won't make it to final output anyways based on approximate size */
    )

select /* pgwatch2_generated */
    epoch_ns,
    tag_schema,
    tag_table_name,
    tag_table_full_name,
    0 as is_part_root,
    table_size_b,
    tag_table_size_cardinality_mb, -- i.e. 0=<1MB, 1=<10MB, 2=<100MB,..
    total_relation_size_b,
    toast_size_b,
    seconds_since_last_vacuum,
    seconds_since_last_analyze,
    no_autovacuum,
    seq_scan,
    seq_tup_read,
    idx_scan,
    idx_tup_fetch,
    n_tup_ins,
    n_tup_upd,
    n_tup_del,
    n_tup_hot_upd,
    n_live_tup,
    n_dead_tup,
    vacuum_count,
    autovacuum_count,
    analyze_count,
    autoanalyze_count,
    tx_freeze_age,
    last_seq_scan_s
from q_tstats
where not tag_schema like E'\\_timescaledb%'
and not exists (select * from q_root_part where oid = q_tstats.relid)

union all

select * from (
    select
        epoch_ns,
        quote_ident(qr.root_schema) as tag_schema,
        quote_ident(qr.root_relname) as tag_table_name,
        quote_ident(qr.root_schema) || '.' || quote_ident(qr.root_relname) as tag_table_full_name,
        1 as is_part_root,
        sum(table_size_b)::int8 table_size_b,
        abs(greatest(ceil(log((sum(table_size_b) + 1) / 10 ^ 6)),
             0))::text as tag_table_size_cardinality_mb, -- i.e. 0=<1MB, 1=<10MB, 2=<100MB,..
        sum(total_relation_size_b)::int8 total_relation_size_b,
        sum(toast_size_b)::int8 toast_size_b,
        min(seconds_since_last_vacuum)::int8 seconds_since_last_vacuum,
        min(seconds_since_last_analyze)::int8 seconds_since_last_analyze,
        sum(no_autovacuum)::int8 no_autovacuum,
        sum(seq_scan)::int8 seq_scan,
        sum(seq_tup_read)::int8 seq_tup_read,
        sum(idx_scan)::int8 idx_scan,
        sum(idx_tup_fetch)::int8 idx_tup_fetch,
        sum(n_tup_ins)::int8 n_tup_ins,
        sum(n_tup_upd)::int8 n_tup_upd,
        sum(n_tup_del)::int8 n_tup_del,
        sum(n_tup_hot_upd)::int8 n_tup_hot_upd,
        sum(n_live_tup)::int8 n_live_tup,
        sum(n_dead_tup)::int8 n_dead_tup,
        sum(vacuum_count)::int8 vacuum_count,
        sum(autovacuum_count)::int8 autovacuum_count,
        sum(analyze_count)::int8 analyze_count,
        sum(autoanalyze_count)::int8 autoanalyze_count,
        max(tx_freeze_age)::int8 tx_freeze_age,
        min(last_seq_scan_s)::int8 last_seq_scan_s
      from
           q_tstats ts
           join q_parts qp on qp.relid = ts.relid
           join q_root_part qr on qr.oid = qp.root
      group by
           1, 2, 3, 4
) x
order by table_size_b desc nulls last limit 300;
