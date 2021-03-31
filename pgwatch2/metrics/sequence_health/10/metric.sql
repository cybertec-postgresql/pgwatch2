select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  (select round(100.0 * coalesce(max(last_value::numeric / max_value), 0), 2) from pg_sequences where not cycle) as max_used_pct,
  (select count(*) from pg_sequences where not cycle and last_value::numeric / max_value > 0.5) as "50p_used_seq_count",
  (select count(*) from pg_sequences where not cycle and last_value::numeric / max_value > 0.75) as "75p_used_seq_count";
