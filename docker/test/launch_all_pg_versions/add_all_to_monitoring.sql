/* primaries */
insert into pgwatch2.monitored_db (md_unique_name, md_preset_config_name, md_config, md_hostname, md_port, md_dbname, md_user, md_password, md_is_superuser)
select 'pg'||pgver, 'exhaustive', null, 'localhost', '543'||pgver, 'postgres', 'postgres', 'postgres', true
from unnest(array[90,91,92,93,94,95,96,10,11,12]) as pgver
where not exists (
        select * from pgwatch2.monitored_db where (md_unique_name, md_hostname, md_dbname) = ('pg'||pgver, 'localhost', 'postgres')
    )
;

/* replicas */
insert into pgwatch2.monitored_db (md_unique_name, md_preset_config_name, md_config, md_hostname, md_port, md_dbname, md_user, md_password, md_is_superuser)
select 'pg'||pgver||'_repl', 'exhaustive', null, 'localhost', ('543'||pgver)::int + 1000, 'postgres', 'postgres', 'postgres', true
from unnest(array[90,91,92,93,94,95,96,10,11,12]) as pgver
where not exists (
        select * from pgwatch2.monitored_db where (md_unique_name, md_hostname, md_dbname) = ('pg'||pgver||'_repl', 'localhost', 'postgres')
    )
;
