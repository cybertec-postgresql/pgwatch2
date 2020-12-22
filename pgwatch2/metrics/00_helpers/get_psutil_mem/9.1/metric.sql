/* Pre-requisites: PL/Pythonu and "psutil" Python package (e.g. pip install psutil) */
CREATE EXTENSION IF NOT EXISTS plpython3u; /* NB! "plpython3u" might need changing to "plpythonu" (Python 2 everywhere for new OS-es */

CREATE OR REPLACE FUNCTION get_psutil_mem(
	OUT total float8, OUT used float8, OUT free float8, OUT buff_cache float8, OUT available float8, OUT percent float8,
	OUT swap_total float8, OUT swap_used float8, OUT swap_free float8, OUT swap_percent float8
)
 LANGUAGE plpython3u
AS $FUNCTION$
from psutil import virtual_memory, swap_memory
vm = virtual_memory()
sw = swap_memory()
return vm.total, vm.used, vm.free, vm.buffers + vm.cached, vm.available, vm.percent, sw.total, sw.used, sw.free, sw.percent
$FUNCTION$;

GRANT EXECUTE ON FUNCTION get_psutil_mem() TO pgwatch2;
COMMENT ON FUNCTION get_psutil_mem() IS 'created for pgwatch2';
