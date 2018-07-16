SELECT
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  cpu_utilization, load_1m_norm, load_1m, load_5m_norm, load_5m,
  "user", system, idle, iowait, irqs, other
from
  public.get_psutil_cpu()
;
