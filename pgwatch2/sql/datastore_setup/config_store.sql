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
    "table_stats": 60,
    "index_stats": 60,
    "stat_statements": 60,
    "sproc_stats": 60
    }'),
    ('exhaustive', 'almost all available metrics for a deeper performance understanding',
    '{
    "backends": 60,
    "bgwriter": 60,
    "cpu_load": 60,
    "db_stats": 60,
    "index_stats": 60,
    "locks": 60,
    "replication": 60,
    "sproc_stats": 60,
    "stat_statements": 60,
    "table_io_stats": 60,
    "table_stats": 60,
    "wal": 60
    }'),
    ('all', 'special setting. all defined (and active) metrics will be gathered. NB! too small intervals could lead to lag',
    '{"all": 60}'
    );  /* TODO */

drop table if exists pgwatch2.monitored_db;

create table pgwatch2.monitored_db (
    md_id serial not null primary key,
    md_unique_name text not null,
    md_hostname text not null,
    md_port text not null default 5432,
    md_dbname text not null,
    md_user text not null,
    md_password text,
    md_preset_config_name text references pgwatch2.preset_config(pc_name) default 'basic',
    md_config jsonb,
    md_is_enabled boolean not null default 't',
    md_ssl_only boolean not null default 'f',   -- gather data only over SSL
    md_last_modified_on timestamptz not null default now(),
    UNIQUE (md_unique_name),
    CONSTRAINT no_colon_on_unique_name CHECK (md_unique_name !~ ':')
);

create unique index on monitored_db(md_hostname, md_port, md_dbname);

alter table pgwatch2.monitored_db add constraint preset_or_custom_config check
    ((not (md_preset_config_name is null and md_config is null))
    and not (md_preset_config_name is not null and md_config is not null));

/* for demo purposes only */
insert into pgwatch2.monitored_db (md_unique_name, md_preset_config_name, md_config, md_hostname, md_port, md_dbname, md_user, md_password)
    values ('test', 'exhaustive', null, 'localhost', '5432', 'pgwatch2', 'pgwatch2', 'pgwatch2admin');


create table pgwatch2.metric (
    m_id                serial primary key,
    m_name              text not null,
    m_pg_version_from   float not null,
    m_sql               text not null,
    m_is_active         boolean not null default 't',
    m_last_modified_on  timestamptz not null default now(),
    unique (m_name, m_pg_version_from)
);

