/* reco_* metrics have special handling - all results are stored actually under one 'recommendations' metric  and
 following text columns are expected:  reco_topic, object_name, recommendation, extra_info.
*/
with q_su as (
  select count(*) from pg_roles where rolcanlogin and rolsuper
),
q_total as (
  select count(*) from pg_roles where rolcanlogin
)
select /* pgwatch2_generated */
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  'superuser_count'::text as tag_reco_topic,
  '-'::text as tag_object_name,
  'too many superusers detected - review recommended'::text as recommendation,
  format('%s active superusers, %s total active users', q_su.count, q_total.count) as extra_info
from
  q_su, q_total
where
  q_su.count >= 10
;