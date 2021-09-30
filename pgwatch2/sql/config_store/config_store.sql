create schema if not exists pgwatch2 authorization pgwatch2;

set search_path to pgwatch2, public;

alter database pgwatch2 set search_path to public, pgwatch2;

set role to pgwatch2; -- NB! Role/db create script is in bootstrap/create_db_pgwatch.sql

-- drop table if exists preset_config cascade;

/* preset configs for typical usecases */
create table if not exists pgwatch2.preset_config (
    pc_name text primary key,
    pc_description text not null,
    pc_config jsonb not null,
    pc_last_modified_on timestamptz not null default now()
);

-- drop table if exists pgwatch2.monitored_db;

create table if not exists pgwatch2.monitored_db (
    md_id serial not null primary key,
    md_unique_name text not null,
    md_hostname text not null,
    md_port text not null default 5432,
    md_dbname text not null,
    md_user text not null,
    md_password text,
    md_is_superuser boolean not null default false,
    md_sslmode text not null default 'disable',  -- set to 'require' for to force SSL
    md_preset_config_name text references pgwatch2.preset_config(pc_name) default 'basic',
    md_config jsonb,
    md_is_enabled boolean not null default 't',
    md_last_modified_on timestamptz not null default now(),
    md_statement_timeout_seconds int not null default 5,   -- metrics queries will be canceled after so many seconds
    md_dbtype text not null default 'postgres',
    md_include_pattern text,    -- valid regex expected. relevant for 'postgres-continuous-discovery'
    md_exclude_pattern text,    -- valid regex expected. relevant for 'postgres-continuous-discovery'
    md_custom_tags jsonb,
    md_group text not null default 'default',
    md_root_ca_path text not null default '',      -- relevant for 'verify-ca', 'verify-full'
    md_client_cert_path text not null default '',  -- relevant for 'verify-full'
    md_client_key_path text not null default '',   -- relevant for 'verify-full'
    md_password_type text not null default 'plain-text',
    md_host_config jsonb,
    md_only_if_master bool not null default false,
    md_preset_config_name_standby text references pgwatch2.preset_config(pc_name),
    md_config_standby jsonb,

    UNIQUE (md_unique_name),
    CONSTRAINT no_colon_on_unique_name CHECK (md_unique_name !~ ':'),
    CHECK (md_sslmode in ('disable', 'require', 'verify-ca', 'verify-full')),
    CHECK (md_dbtype in ('postgres', 'pgbouncer', 'postgres-continuous-discovery', 'patroni', 'patroni-continuous-discovery', 'patroni-namespace-discovery', 'pgpool')),
    CHECK (md_group ~ E'\\w+'),
    CHECK (md_password_type in ('plain-text', 'aes-gcm-256'))
);

-- prevent multiple active workers for the same db
create unique index if not exists monitored_db_md_hostname_md_port_md_dbname_md_is_enabled_idx on monitored_db(md_hostname, md_port, md_dbname, md_is_enabled) where not md_dbtype ~ 'patroni';


alter table pgwatch2.monitored_db add constraint preset_or_custom_config check
    ((not (md_preset_config_name is null and md_config is null))
    and not (md_preset_config_name is not null and md_config is not null)),

    add constraint preset_or_custom_config_standby check (
    not (md_preset_config_name_standby is not null and md_config_standby is not null));


create table if not exists metric (
    m_id                serial primary key,
    m_name              text not null,
    m_pg_version_from   numeric not null,
    m_sql               text not null,
    m_comment           text,
    m_is_active         boolean not null default 't',
    m_is_helper         boolean not null default 'f',
    m_last_modified_on  timestamptz not null default now(),
    m_master_only       bool not null default false,
    m_standby_only      bool not null default false,
    m_column_attrs      jsonb,  -- currently only useful for Prometheus
    m_sql_su            text default '',

    unique (m_name, m_pg_version_from, m_standby_only),
    check (not (m_master_only and m_standby_only)),
    check (m_name ~ E'^[a-z0-9_\\.]+$')
);

create table metric_attribute (
    ma_metric_name          text not null primary key,
    ma_last_modified_on     timestamptz not null default now(),
    ma_metric_attrs    jsonb not null,

    check (ma_metric_name ~ E'^[a-z0-9_\\.]+$')
);


/* this should allow auto-rollout of schema changes for future (1.6+) releases. currently only informative */
create table if not exists schema_version (
    sv_tag text primary key,
    sv_created_on timestamptz not null default now()
);

insert into pgwatch2.schema_version (sv_tag) values ('1.8.5');


insert into pgwatch2.preset_config (pc_name, pc_description, pc_config)
    values ('minimal', 'single "Key Performance Indicators" query for fast cluster/db overview',
    '{
    "kpi": 60
    }'),
    ('basic', 'only the most important metrics - WAL, DB-level statistics (size, tx and backend counts)',
    '{
    "wal": 60,
    "db_stats": 60,
    "db_size": 300
    }'),
    ('standard', '"basic" level + table, index, stat_statements stats',
    '{
    "cpu_load": 60,
    "wal": 60,
    "db_stats": 60,
    "db_size": 300,
    "table_stats": 300,
    "index_stats": 900,
    "sequence_health": 3600,
    "stat_statements": 180,
    "sproc_stats": 180
    }'),
    ('pgbouncer', 'per DB stats',
    '{
    "pgbouncer_stats": 60
    }'),
    ('pgpool', 'pool global stats, 1 row per node ID',
    '{
    "pgpool_stats": 60
    }'),
    ('exhaustive', 'all important metrics for a deeper performance understanding',
    '{
    "archiver": 60,
    "backends": 60,
    "bgwriter": 60,
    "cpu_load": 60,
    "db_stats": 60,
    "db_size": 300,
    "index_stats": 900,
    "locks": 60,
    "locks_mode": 60,
    "replication": 120,
    "replication_slots": 120,
    "settings": 7200,
    "sequence_health": 3600,
    "sproc_stats": 180,
    "stat_statements": 180,
    "stat_statements_calls": 60,
    "table_io_stats": 600,
    "table_stats": 300,
    "wal": 60,
    "wal_size": 300,
    "wal_receiver": 120,
    "change_events": 300,
    "table_bloat_approx_summary_sql": 7200
    }'),
    ('full', 'almost all available metrics for a even deeper performance understanding',
    '{
    "archiver": 60,
    "backends": 60,
    "bgwriter": 60,
    "cpu_load": 60,
    "db_stats": 60,
    "db_size": 300,
    "index_stats": 900,
    "instance_up": 60,
    "locks": 60,
    "locks_mode": 60,
    "recommendations": 43200,
    "replication": 120,
    "replication_slots": 120,
    "logical_subscriptions": 120,
    "server_log_event_counts": 60,
    "settings": 7200,
    "sequence_health": 3600,
    "sproc_stats": 180,
    "stat_statements": 180,
    "stat_statements_calls": 60,
    "table_io_stats": 600,
    "table_stats": 300,
    "wal": 60,
    "wal_size": 120,
    "change_events": 300,
    "table_bloat_approx_summary_sql": 7200,
    "kpi": 120,
    "stat_ssl": 120,
    "psutil_cpu": 120,
    "psutil_mem": 120,
    "psutil_disk": 120,
    "psutil_disk_io_total": 120,
    "wal_receiver": 120
    }'),
    ('full_influx', 'almost all available metrics for a even deeper performance understanding',
    '{
    "archiver": 60,
    "backends": 60,
    "bgwriter": 60,
    "cpu_load": 60,
    "db_stats": 60,
    "db_size": 300,
    "index_stats": 900,
    "locks": 60,
    "locks_mode": 60,
    "recommendations": 43200,
    "replication": 120,
    "replication_slots": 120,
    "logical_subscriptions": 120,
    "server_log_event_counts": 60,
    "settings": 7200,
    "sequence_health": 3600,
    "sproc_stats": 180,
    "stat_statements": 180,
    "stat_statements_calls": 60,
    "table_io_stats": 600,
    "table_stats": 300,
    "wal": 60,
    "wal_size": 120,
    "change_events": 300,
    "table_bloat_approx_summary_sql": 7200,
    "kpi": 120,
    "stat_ssl": 120,
    "psutil_cpu": 120,
    "psutil_mem": 120,
    "psutil_disk": 120,
    "psutil_disk_io_total": 120,
    "wal_receiver": 120
    }'),
    ('unprivileged', 'no wrappers + only pg_stat_statements extension expected (developer mode)',
    '{
    "archiver": 60,
    "bgwriter": 60,
    "db_stats": 60,
    "db_size": 300,
    "index_stats": 900,
    "locks": 60,
    "locks_mode": 60,
    "replication": 120,
    "replication_slots": 120,
    "settings": 7200,
    "sequence_health": 3600,
    "sproc_stats": 180,
    "stat_statements_calls": 60,
    "table_io_stats": 600,
    "table_stats": 300,
    "wal": 60,
    "change_events": 300
    }'),
    ('prometheus', 'similar to "exhaustive" but without some possibly longer-running metrics and those keeping state',
    '{
    "archiver": 1,
    "backends": 1,
    "bgwriter": 1,
    "cpu_load": 1,
    "db_stats": 1,
    "db_size": 1,
    "locks_mode": 1,
    "replication": 1,
    "replication_slots": 1,
    "sproc_stats": 1,
    "stat_statements_calls": 1,
    "table_stats": 1,
    "wal": 1,
    "wal_receiver": 1
    }'),
    ('prometheus-async', 'tuned for the new async (background collection) Prom feature. NB! Prom tolerates max. 10min time lag, so intervals should be smaller than 600',
    '{
    "archiver": 60,
    "backends": 60,
    "bgwriter": 60,
    "db_stats": 60,
    "db_size": 300,
    "locks": 60,
    "locks_mode": 60,
    "replication": 120,
    "replication_slots": 120,
    "settings": 300,
    "sequence_health": 300,
    "sproc_stats": 180,
    "stat_statements_calls": 60,
    "table_io_stats": 300,
    "table_stats": 300,
    "wal": 60
    }'),
   ('superuser_no_python', 'like exhaustive, but no PL/Python helpers',
    '{
      "archiver": 60,
      "backends": 60,
      "bgwriter": 60,
      "db_stats": 60,
      "db_size": 300,
      "index_stats": 900,
      "locks": 60,
      "locks_mode": 60,
      "replication": 120,
      "replication_slots": 120,
      "settings": 7200,
      "sequence_health": 3600,
      "sproc_stats": 180,
      "stat_statements": 180,
      "stat_statements_calls": 60,
      "table_io_stats": 600,
      "table_stats": 300,
      "wal": 60,
      "wal_size": 300,
      "wal_receiver": 120,
      "change_events": 300,
      "table_bloat_approx_summary_sql": 7200
    }'),
   ('aurora', 'AWS Aurora doesn''t expose all Postgres functions and there''s no WAL',
    '{
      "archiver": 60,
      "backends": 60,
      "bgwriter": 60,
      "db_stats_aurora": 60,
      "db_size": 300,
      "index_stats": 900,
      "locks": 60,
      "locks_mode": 60,
      "replication": 120,
      "replication_slots": 120,
      "settings": 7200,
      "sproc_stats": 180,
      "stat_statements": 180,
      "stat_statements_calls": 60,
      "table_io_stats": 600,
      "table_stats": 300,
      "wal_receiver": 120,
      "change_events": 300,
      "table_bloat_approx_summary_sql": 7200
    }'),
   ('azure', 'similar to ''exhaustive'' with stuff that''s not accessible on Azure Database for PostgreSQL removed',
    '{
      "kpi": 120,
      "wal": 60,
      "wal_size": 300,
      "locks": 60,
      "db_size": 300,
      "archiver": 60,
      "backends": 60,
      "bgwriter": 60,
      "db_stats": 60,
      "settings": 7200,
      "stat_ssl": 60,
      "locks_mode": 60,
      "index_stats": 900,
      "replication": 60,
      "sproc_stats": 180,
      "wal_receiver": 60,
      "change_events": 300,
      "table_io_stats": 600,
      "stat_statements": 180,
      "sequence_health": 3600,
      "replication_slots": 60,
      "stat_statements_calls": 60,
      "table_bloat_approx_summary_sql": 7200
    }'),
   ('rds', 'similar to ''exhaustive'' with stuff not accessible on AWS RDS removed',
    '{
    "archiver": 60,
    "backends": 60,
    "bgwriter": 60,
    "change_events": 300,
    "db_stats": 60,
    "db_size": 300,
    "index_stats": 900,
    "locks": 60,
    "locks_mode": 60,
    "replication": 120,
    "replication_slots": 120,
    "settings": 7200,
    "sequence_health": 3600,
    "sproc_stats": 180,
    "stat_statements": 180,
    "stat_statements_calls": 60,
    "table_bloat_approx_summary_sql": 7200,
    "table_io_stats": 600,
    "table_stats": 300,
    "wal": 60,
    "wal_receiver": 120
    }'),
    ('gce', 'similar to ''exhaustive'' with stuff not accessible on GCE managed PostgreSQL engine removed',
     '{
       "archiver": 60,
       "backends": 60,
       "bgwriter": 60,
       "db_stats": 60,
       "db_size": 300,
       "index_stats": 900,
       "locks": 60,
       "locks_mode": 60,
       "replication": 120,
       "replication_slots": 120,
       "settings": 7200,
       "sequence_health": 3600,
       "sproc_stats": 180,
       "stat_statements": 180,
       "stat_statements_calls": 60,
       "table_io_stats": 600,
       "table_stats": 300,
       "wal": 60,
       "wal_receiver": 120,
       "change_events": 300,
       "table_bloat_approx_summary_sql": 7200
     }');

/* one host for demo purposes, so that "docker run" could immediately show some graphs */
--insert into pgwatch2.monitored_db (md_unique_name, md_preset_config_name, md_config, md_hostname, md_port, md_dbname, md_user, md_password)
--    values ('test', 'exhaustive', null, 'localhost', '5432', 'pgwatch2', 'pgwatch2', 'pgwatch2admin');
