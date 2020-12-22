/*  Pre-requisites: PL/Pythonu and "psutil" Python package (e.g. pip install psutil)
    NB! "psutil" is known to behave differently depending on the used version and operating system, so if getting
    errors please adjust to your needs. "psutil" documentation here: https://psutil.readthedocs.io/en/latest/
*/
CREATE EXTENSION IF NOT EXISTS plpython3u; /* NB! "plpython3u" might need changing to "plpythonu" (Python 2) everywhere for older OS-es */

CREATE OR REPLACE FUNCTION get_psutil_cpu(
	OUT cpu_utilization float8, OUT load_1m_norm float8, OUT load_1m float8, OUT load_5m_norm float8, OUT load_5m float8,
    OUT "user" float8, OUT system float8, OUT idle float8, OUT iowait float8, OUT irqs float8, OUT other float8
)
 LANGUAGE plpython3u
AS $FUNCTION$

from os import getloadavg
from psutil import cpu_times_percent, cpu_percent, cpu_count
from threading import Thread

class GetCpuPercentThread(Thread):
    def __init__(self, interval_seconds):
        self.interval_seconds = interval_seconds
        self.cpu_utilization_info = None
        super(GetCpuPercentThread, self).__init__()

    def run(self):
        self.cpu_utilization_info = cpu_percent(self.interval_seconds)

t = GetCpuPercentThread(0.5)
t.start()

ct = cpu_times_percent(0.5)
la = getloadavg()

t.join()

return t.cpu_utilization_info, la[0] / cpu_count(), la[0], la[1] / cpu_count(), la[1], ct.user, ct.system, ct.idle, ct.iowait, ct.irq + ct.softirq, ct.steal + ct.guest + ct.guest_nice

$FUNCTION$;

GRANT EXECUTE ON FUNCTION get_psutil_cpu() TO pgwatch2;
COMMENT ON FUNCTION get_psutil_cpu() IS 'created for pgwatch2';
