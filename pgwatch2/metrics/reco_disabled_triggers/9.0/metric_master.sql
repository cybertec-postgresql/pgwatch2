/* "temporarily" disabled triggers might be forgotten about... */
select /* pgwatch2_generated */
    (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
    'disabled_triggers'::text as tag_reco_topic,
    quote_ident(nspname)||'.'||quote_ident(relname) as tag_object_name,
    'review usage of trigger and consider dropping it if not needed anymore'::text as recommendation,
    ''::text as extra_info
from
    pg_trigger t
    join
    pg_class c on c.oid = t.tgrelid
    join
    pg_namespace n on n.oid = c.relnamespace
where
    tgenabled = 'D'
;
