begin;

alter table pgwatch2.monitored_db
    add md_host_config jsonb,
    drop constraint monitored_db_md_dbtype_check,
    add constraint monitored_db_md_dbtype_check
      check (md_dbtype in ('postgres', 'pgbouncer', 'postgres-continuous-discovery', 'patroni'));

alter table pgwatch2.monitored_db
    add md_only_if_master bool not null default false;

commit;
