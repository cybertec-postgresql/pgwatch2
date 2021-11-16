select /* pgwatch2_generated */
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  read_count,
  write_count,
  read_bytes,
  write_bytes
from
  get_psutil_disk_io_total()
;
