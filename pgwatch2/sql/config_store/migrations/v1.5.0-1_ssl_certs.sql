begin;

alter table monitored_db
  add md_root_ca_path text not null default '',
  add md_client_cert_path text not null default '',
  add md_client_key_path text not null default '';
  
alter table monitored_db
    drop constraint monitored_db_md_sslmode_check,
    add constraint monitored_db_md_sslmode_check
        CHECK (md_sslmode in ('disable', 'require', 'verify-ca', 'verify-full'));

commit;
