/* Pre-requisites: PL/Pythonu and "psutil" Python package (e.g. pip install psutil) */
CREATE EXTENSION IF NOT EXISTS plpython3u; /* NB! "plpython3u" might need changing to "plpythonu" (Python 2) everywhere for older OS-es */

CREATE OR REPLACE FUNCTION get_psutil_disk_io_total(
	OUT read_count float8, OUT write_count float8, OUT read_bytes float8, OUT write_bytes float8
)
 LANGUAGE plpython3u
AS $FUNCTION$
from psutil import disk_io_counters
dc = disk_io_counters(perdisk=False)
if dc:
    return dc.read_count, dc.write_count, dc.read_bytes, dc.write_bytes
else:
    return None, None, None, None
$FUNCTION$;

GRANT EXECUTE ON FUNCTION get_psutil_disk_io_total() TO pgwatch2;
COMMENT ON FUNCTION get_psutil_disk_io_total() IS 'created for pgwatch2';
