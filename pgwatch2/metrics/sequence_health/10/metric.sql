with q_seq_data as (
    select * from get_sequences()
)
select /* pgwatch2_generated */
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  (select round(100.0 * coalesce(max(last_value::numeric / max_value), 0), 2)::float from q_seq_data where not cycle) as max_used_pct,
  (select count(*) from q_seq_data where not cycle and last_value::numeric / max_value > 0.5) as p50_used_seq_count,
  (select count(*) from q_seq_data where not cycle and last_value::numeric / max_value > 0.75) as p75_used_seq_count;
