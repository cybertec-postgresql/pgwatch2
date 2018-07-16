/* Pre-requisites: PL/Pythonu and "psutil" Python package (e.g. pip install psutil) */

CREATE OR REPLACE FUNCTION public.get_psutil_cpu_info(
	OUT cpu_utilization float8, OUT load_1m_norm float8, OUT load_1m float8, OUT load_5m_norm float8, OUT load_5m float8,
    OUT "user" float8, OUT system float8, OUT idle float8, OUT iowait float8, OUT irqs float8, OUT other float8
)
 LANGUAGE plpythonu
 SECURITY DEFINER
AS $FUNCTION$
from os import getloadavg
from psutil import cpu_times_percent, cpu_percent, cpu_count
ct = cpu_times_percent()
la = getloadavg()
return cpu_percent(1), la[0] / cpu_count(), la[0], la[1] / cpu_count(), la[1], ct.user, ct.system, ct.idle, ct.iowait, ct.irq + ct.softirq, ct.steal + ct.guest + ct.guest_nice
$FUNCTION$;

REVOKE EXECUTE ON FUNCTION public.get_psutil_cpu_info() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_psutil_cpu_info() TO pgwatch2;
COMMENT ON FUNCTION public.get_psutil_cpu_info() IS 'created for pgwatch2';
