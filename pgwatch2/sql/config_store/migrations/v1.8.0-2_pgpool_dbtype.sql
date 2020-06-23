begin;

alter table pgwatch2.monitored_db
    drop constraint monitored_db_md_dbtype_check,
    add constraint monitored_db_md_dbtype_check
        check (md_dbtype in ('postgres', 'pgbouncer', 'postgres-continuous-discovery', 'patroni', 'patroni-continuous-discovery', 'pgpool'));

insert into pgwatch2.schema_version (sv_tag) values ('1.8.0')
  on conflict do nothing;

commit;
