begin;
  alter table pgwatch2.monitored_db
    add md_group text not null default 'default' check (md_group ~ E'\\w+');
commit;

