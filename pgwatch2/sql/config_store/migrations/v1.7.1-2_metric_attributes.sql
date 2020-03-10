begin;

set role to pgwatch2;

create table pgwatch2.metric_attribute (
    ma_metric_name          text not null primary key,
    ma_last_modified_on     timestamptz not null default now(),
    ma_metric_attrs    jsonb not null,

    check (ma_metric_name ~ '^[a-z0-9_]+$')
);

insert into pgwatch2.metric_attribute (ma_metric_name, ma_metric_attrs)
select m, '{"is_instance_level": true}'
from unnest(
   array['archiver', 'backup_age_pgbackrest', 'backup_age_walg', 'bgwriter', 'buffercache_by_db', 'buffercache_by_type',
  'cpu_load', 'psutil_cpu', 'psutil_disk', 'psutil_disk_io_total', 'psutil_mem', 'replication', 'replication_slots',
  'smart_health_per_disk', 'wal', 'wal_receiver', 'wal_size']
) m;

insert into pgwatch2.schema_version (sv_tag) values ('1.7.1');

end;
