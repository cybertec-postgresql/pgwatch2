/* assumes the pg_qualstats extension and superuser or select grant on pg_qualstats_index_advisor() function */
select /* pgwatch2_generated */
  epoch_ns,
  tag_reco_topic,
  tag_object_name,
  recommendation,
  case when exists (select * from pg_inherits
                    where inhrelid = regclass(tag_object_name)
                    ) then 'NB! Partitioned table, create the index on parent' else extra_info
  end as extra_info
FROM (
         SELECT (extract(epoch from now()) * 1e9)::int8    as epoch_ns,
                'create_index'::text                       as tag_reco_topic,
                (regexp_matches(v::text, E'ON (.*?) '))[1] as tag_object_name,
                v::text                                    as recommendation,
                ''                                         as extra_info
         FROM json_array_elements(
                      pg_qualstats_index_advisor() -> 'indexes') v
     ) x
ORDER BY tag_object_name;
