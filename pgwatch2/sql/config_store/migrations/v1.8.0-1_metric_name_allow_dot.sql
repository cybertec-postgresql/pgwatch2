begin;

alter table pgwatch2.metric
    drop constraint metric_m_name_check,
    add constraint metric_m_name_check check (m_name ~ E'^[a-z0-9_\\.]+$');

alter table pgwatch2.metric_attribute
    drop constraint metric_attribute_ma_metric_name_check,
    add constraint metric_attribute_ma_metric_name_check check (ma_metric_name ~ E'^[a-z0-9_\\.]+$');

commit;
