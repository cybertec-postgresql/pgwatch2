select /* pgwatch2_generated */
   (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
   checkpoints_timed,
   checkpoints_req,
   buffers_checkpoint,
   buffers_clean,
   maxwritten_clean,
   buffers_backend,
   buffers_alloc
 from
   pg_stat_bgwriter;
