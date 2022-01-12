select /* pgwatch2_generated */
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  device as tag_device,
  retcode
from
  get_smart_health_per_device();
