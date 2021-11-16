select /* pgwatch2_generated */
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  round(cpu_utilization::numeric, 2)::float as cpu_utilization,
  round(load_1m_norm::numeric, 2)::float as load_1m_norm,
  round(load_1m::numeric, 2)::float as load_1m,
  round(load_5m_norm::numeric, 2)::float as load_5m_norm,
  round(load_5m::numeric, 2)::float as load_5m,
  round("user"::numeric, 2)::float as "user",
  round(system::numeric, 2)::float as system,
  round(idle::numeric, 2)::float as idle,
  round(iowait::numeric, 2)::float as iowait,
  round(irqs::numeric, 2)::float as irqs,
  round(other::numeric, 2)::float as other
from
  get_psutil_cpu()
;
