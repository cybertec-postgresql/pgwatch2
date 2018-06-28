select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  load_1min,
  load_5min,
  load_15min
from
  public.get_load_average();   -- needs the plpythonu proc from "metric_fetching_helpers" folder
