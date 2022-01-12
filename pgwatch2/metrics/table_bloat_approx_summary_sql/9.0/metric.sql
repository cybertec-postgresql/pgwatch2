WITH q_bloat AS (
    select * from get_table_bloat_approx_sql()
)
select /* pgwatch2_generated */
    (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
    (select sum(approx_bloat_bytes) from q_bloat) as approx_table_bloat_b,
    ((select sum(approx_bloat_bytes) from q_bloat) * 100 / pg_database_size(current_database()))::int8 as approx_bloat_percentage
;
