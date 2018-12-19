begin;

alter table monitored_db
  add md_password_type text not null default 'plain-text'
  CHECK (md_password_type in ('plain-text', 'aes-gcm-256'));

commit;
