/* NB! using superuser for monitoring is not a best practice and should be done only if pgwatch2 is also running locally */
insert into pgwatch2.monitored_db (md_unique_name, md_preset_config_name, md_config, md_hostname, md_port, md_dbname, md_user, md_password)
  select 'test', 'full_influx', null, 'localhost', '5432', 'pgwatch2', 'postgres', ''
  where not exists (
      select * from pgwatch2.monitored_db where (md_unique_name, md_hostname, md_dbname) = ('test', 'localhost', 'pgwatch2')
  )
;
