with q_sr as (
  select * from pg_subscription_rel
)
select /* pgwatch2_generated */
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  subname::text as tag_subname,
  subenabled,
  (select count(*) from q_sr where srsubid = oid) as relcount,
  (select count(*) from q_sr where srsubid = oid and srsubstate = 'i') as state_i,
  (select count(*) from q_sr where srsubid = oid and srsubstate = 'd') as state_d,
  (select count(*) from q_sr where srsubid = oid and srsubstate = 's') as state_s,
  (select count(*) from q_sr where srsubid = oid and srsubstate = 'r') as state_r
from
  pg_subscription
where
  subdbid = (select oid from pg_database where datname = current_database())
;