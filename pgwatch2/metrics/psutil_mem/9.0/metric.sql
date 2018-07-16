SELECT
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  total, used, free, shared, buff_cache, available, percent,
  swap_total, swap_used, swap_free, swap_percent
from
  public.get_psutil_mem()
;
