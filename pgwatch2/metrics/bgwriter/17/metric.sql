select /* pgwatch2_generated */
   (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
   buffers_clean,
   maxwritten_clean,
   buffers_alloc,
   (extract(epoch from now() - stats_reset))::int as last_reset_s
 from
   pg_stat_bgwriter;
