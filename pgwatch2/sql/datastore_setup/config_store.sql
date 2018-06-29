create schema if not exists pgwatch2 authorization pgwatch2;

REVOKE ALL ON SCHEMA public FROM public;

GRANT ALL ON SCHEMA public TO pgwatch2;

create extension if not exists pg_stat_statements; -- NB! for demo purposes only, can fail

create extension if not exists plpythonu; -- NB! for demo purposes only, to enable CPU load gathering

set search_path to pgwatch2, public;

alter database pgwatch2 set search_path to pgwatch2, public;

set role to pgwatch2; -- NB! Role/db create script is in bootstrap/create_db_pgwatch.sql

drop table if exists preset_config cascade;

/* preset configs for typical usecases */
create table pgwatch2.preset_config (
    pc_name text primary key,
    pc_description text not null,
    pc_config jsonb not null,
    pc_last_modified_on timestamptz not null default now()
);

drop table if exists pgwatch2.monitored_db;

create table pgwatch2.monitored_db (
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
    UNIQUE (md_unique_name),
    CONSTRAINT no_colon_on_unique_name CHECK (md_unique_name !~ ':'),
    CHECK (md_sslmode in ('disable', 'require', 'verify-full')),
    CHECK (md_dbtype in ('postgres', 'pgbouncer', 'postgres-continuous-discovery'))
);

create unique index on monitored_db(md_hostname, md_port, md_dbname, md_is_enabled); -- prevent multiple active workers for the same db


alter table pgwatch2.monitored_db add constraint preset_or_custom_config check
    ((not (md_preset_config_name is null and md_config is null))
    and not (md_preset_config_name is not null and md_config is not null));


create table pgwatch2.metric (
    m_id                serial primary key,
    m_name              text not null,
    m_pg_version_from   numeric not null,
    m_sql               text not null,
    m_comment           text,
    m_is_active         boolean not null default 't',
    m_is_helper         boolean not null default 'f',
    m_last_modified_on  timestamptz not null default now(),
    unique (m_name, m_pg_version_from)
);


insert into pgwatch2.preset_config (pc_name, pc_description, pc_config)
    values ('minimal', 'single "Key Performance Indicators" query for fast cluster/db overview',
    '{
    "kpi": 60
    }'),
    ('basic', 'only the most important metrics - load, WAL, DB-level statistics (size, tx and backend counts)',
    '{
    "cpu_load": 60,
    "wal": 60,
    "db_stats": 60
    }'),
    ('standard', '"basic" level + table, index, stat_statements stats',
    '{
    "cpu_load": 60,
    "wal": 60,
    "db_stats": 60,
    "table_stats": 120,
    "index_stats": 120,
    "stat_statements": 120,
    "sproc_stats": 120
    }'),
    ('pgbouncer', 'per DB stats',
    '{
    "pgbouncer_stats": 60
    }'),
    ('exhaustive', 'almost all available metrics for a deeper performance understanding',
    '{
    "backends": 60,
    "bgwriter": 60,
    "cpu_load": 60,
    "db_stats": 60,
    "index_stats": 120,
    "locks": 60,
    "locks_mode": 60,
    "replication": 60,
    "sproc_stats": 60,
    "stat_statements": 120,
    "stat_statements_calls": 60,
    "table_io_stats": 120,
    "table_stats": 120,
    "wal": 60,
    "change_events": 300,
    "table_bloat_approx_summary": 7200
    }');

/* one host for demo purposes, so that "docker run" could immediately show some graphs */
--insert into pgwatch2.monitored_db (md_unique_name, md_preset_config_name, md_config, md_hostname, md_port, md_dbname, md_user, md_password)
--    values ('test', 'exhaustive', null, 'localhost', '5432', 'pgwatch2', 'pgwatch2', 'pgwatch2admin');
