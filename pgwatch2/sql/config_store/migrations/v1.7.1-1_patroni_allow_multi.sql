begin;

drop index monitored_db_md_hostname_md_port_md_dbname_md_is_enabled_idx;

create unique index on monitored_db(md_hostname, md_port, md_dbname, md_is_enabled) where not md_dbtype ~ 'patroni';

end;
