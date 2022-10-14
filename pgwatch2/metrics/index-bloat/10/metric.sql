/* NB! accessing pgstattuple_approx directly requires superuser or pg_stat_scan_tables/pg_monitor builtin roles */
WITH q_locked_rels AS (
    select relation from pg_locks where mode = 'AccessExclusiveLock' and granted
),
q_index_details AS (
    select
        sui.schemaname,
        sui.indexrelname,
	    sui.relname,
        case 
            when ((pgstatindex(sui.indexrelid)).leaf_fragmentation)::numeric = 'NaN' then 0
            else ((pgstatindex(sui.indexrelid)).leaf_fragmentation)
        end as leaf_fragmentation    
    from
        pg_stat_user_indexes sui
    where not sui.schemaname like any (array [E'pg\\_temp%', E'\\_timescaledb%'])
    and not exists (select * from q_locked_rels where relation = sui.relid or relation = sui.indexrelid)
)
select  
    (extract(epoch from now()) * 1e9)::int8 as epoch_ns, 
    quote_ident(schemaname)||'.'||quote_ident(relname) tag_table_full_name,
    quote_ident(indexrelname)as tag_index_full_name,
    leaf_fragmentation
from q_index_details 
where leaf_fragmentation>=40;