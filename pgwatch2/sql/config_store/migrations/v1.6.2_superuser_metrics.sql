begin;

alter table pgwatch2.metric add m_sql_su text default '';

insert into pgwatch2.schema_version (sv_tag) values ('1.6.2');

commit;
