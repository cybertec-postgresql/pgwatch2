select /* pgwatch2_generated */
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  approx_free_percent,
  approx_free_space as approx_free_space_b,
  dead_tuple_percent,
  dead_tuple_len as dead_tuple_len_b
from
  get_table_bloat_approx()
where
  approx_free_space > 0;
