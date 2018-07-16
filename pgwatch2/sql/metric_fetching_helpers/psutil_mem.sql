/* Pre-requisites: PL/Pythonu and "psutil" Python package (e.g. pip install psutil) */

CREATE OR REPLACE FUNCTION public.get_psutil_meminfo(
	OUT total float8, OUT used float8, OUT free float8, OUT shared float8, OUT buff_cache float8, OUT available float8, OUT percent float8,
	OUT swap_total float8, OUT swap_used float8, OUT swap_free float8, OUT swap_percent float8
)
 LANGUAGE plpythonu
 SECURITY DEFINER
AS $FUNCTION$
from psutil import virtual_memory, swap_memory
vm = virtual_memory()
sw = swap_memory()
return vm.total, vm.used, vm.free, vm.shared, vm.buffers + vm.cached, vm.available, vm.percent, sw.total, sw.used, sw.free, sw.percent
$FUNCTION$;

REVOKE EXECUTE ON FUNCTION public.get_psutil_meminfo() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_psutil_meminfo() TO pgwatch2;
COMMENT ON FUNCTION public.get_psutil_meminfo() IS 'created for pgwatch2';
