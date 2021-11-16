/* NB! If using not a real superuser but a role with "pg_monitor" grant then below execute grant is needed:
  GRANT EXECUTE ON FUNCTION pg_stat_file(text) to pgwatch2;
*/
select /* pgwatch2_generated */
    (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
    (sum((pg_stat_file('pg_wal/' || name)).size))::int8 as wal_size_b
from pg_ls_waldir();
