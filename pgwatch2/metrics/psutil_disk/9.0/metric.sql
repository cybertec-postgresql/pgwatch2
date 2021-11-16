select /* pgwatch2_generated */
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  dir_or_tablespace as tag_dir_or_tablespace,
  path as tag_path,
  total, used, free, percent
from
  get_psutil_disk()
;
