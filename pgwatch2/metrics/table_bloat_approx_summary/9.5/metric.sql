select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  approx_free_percent,
  approx_free_space as approx_free_space_b
from
  public.get_table_bloat_approx()
where
  approx_free_space > 0
