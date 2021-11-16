/* NB! This metric has some special handling attached to it - it will store a 0 value if the DB is not accessible.
   Thus it can be used to for example calculate some percentual "uptime" indicator.
*/
select /* pgwatch2_generated */
    (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
    1::int as is_up
;
