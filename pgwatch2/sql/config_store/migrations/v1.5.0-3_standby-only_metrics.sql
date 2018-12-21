begin;

alter table metric
  add m_master_only bool default false,
  add m_standby_only bool default false;

alter table metric
  add constraint metric_check check (not (m_master_only and m_standby_only));

commit;
