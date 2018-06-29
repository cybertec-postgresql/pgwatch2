begin;

alter table pgwatch2.monitored_db
    add md_include_pattern text,
    add md_exclude_pattern text,
    drop constraint monitored_db_md_dbtype_check,
    add constraint monitored_db_md_dbtype_check check (md_dbtype in ('postgres', 'pgbouncer', 'postgres-continuous-discovery'));

alter table pgwatch2.monitored_db
    add md_custom_tags jsonb;

commit;
