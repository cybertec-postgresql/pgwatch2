select /* pgwatch2_generated */
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  round(load_1min::numeric, 2)::float as load_1min,
  round(load_5min::numeric, 2)::float as load_5min,
  round(load_15min::numeric, 2)::float as load_15min
from
  get_load_average();   -- needs the plpythonu proc from "metric_fetching_helpers" folder
