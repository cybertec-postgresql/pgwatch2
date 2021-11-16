select /* pgwatch2_generated */
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  total, used, free, buff_cache, available, percent,
  swap_total, swap_used, swap_free, swap_percent
from
  get_psutil_mem()
;
