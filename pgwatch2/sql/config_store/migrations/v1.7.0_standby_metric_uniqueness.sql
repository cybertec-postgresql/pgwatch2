begin;

alter table pgwatch2.metric
    alter column m_master_only set not null,
    alter column m_standby_only set not null,
    drop constraint metric_m_name_m_pg_version_from_key,
    add constraint metric_m_name_m_pg_version_from_ke UNIQUE (m_name, m_pg_version_from, m_standby_only);

insert into pgwatch2.schema_version (sv_tag) values ('1.7.0');

commit;
