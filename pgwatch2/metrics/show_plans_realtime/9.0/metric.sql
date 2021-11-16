/* assumes pg_show_plans extension */
select /* pgwatch2_generated */
  max((extract(epoch from now()) * 1e9)::int8) as epoch_ns,
  max(extract(epoch from now() - query_start))::int as max_s,
  avg(extract(epoch from now() - query_start))::int as avg_s,
  count(*),
  array_to_string(array_agg(distinct usename order by usename), ',') as "users",
  max(md5(plan)) as tag_hash, /* needed for influx */
  plan,
  max(query) as query
from
  pg_show_plans p
  join
  pg_stat_activity a
    using (pid)
where
  p.pid != pg_backend_pid()
  and datname = current_database()
  and now() - query_start > '1s'::interval
group by
  plan
order by
  max_s desc
limit
  10
;