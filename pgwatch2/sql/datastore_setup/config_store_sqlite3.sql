drop table if exists preset_config;

-- preset configs for typical usecases
create table preset_config (
    pc_name text primary key,
    pc_description text not null,
    pc_config json not null,
    pc_created_on datetime not null default CURRENT_TIMESTAMP,
    pc_last_modified_on datetime
);

insert into preset_config (pc_name, pc_description, pc_config)
    values ('minimal', 'single "Key Performance Indicators" query for fast cluster/db overview',
    '{
    "kpi": 300
    }'),
    ('basic', 'only the most important metrics - load, WAL, DB-level statistics (size, tx and backend counts)',
    '{
    "cpu_load": 300,
    "wal": 300,
    "db_size": 300,
    "db_stats": 300
    }'),
    ('standard', '"basic" level + table, index, stat_statements stats',
    '{
    "cpu_load": 300,
    "wal": 300,
    "db_size": 300,
    "db_stats": 300,
    "table_stats": 300,
    "index_stats": 300,
    "stat_statements": 300,
    "sproc_stats": 300
    }'),
    ('exhaustive', 'everything. all subfolder names under "metrics_sql" should be here',
    '{
    "cpu_load": 300,
    "wal": 300,
    "db_size": 300,
    "db_stats": 300,
    "table_stats": 300,
    "table_io_stats": 300,
    "index_stats": 300,
    "stat_statements": 300,
    "sproc_stats": 300,
    "bgwriter": 300,
    "replication": 300,
    "locks": 60,
    "backends": 60
    }'
    );


drop table if exists monitored_db;

create table monitored_db (
    md_unique_name text not null primary key,
    md_preset_config text references preset_config(pc_name) default 'basic',
    md_custom_config json,
    md_is_active boolean not null default 't'
    md_hostname text not null,
    md_port text not null default 5432,
    md_dbname text not null,
    md_user text not null,
    md_password text,
    md_is_password_encrypted boolean not null default false, --TODO
    md_created_on datetime not null default CURRENT_TIMESTAMP,
    md_last_modified_on datetime,
    md_host_group text not null default 'group1',
    md_gatherer_group text not null default 'group1',
);

