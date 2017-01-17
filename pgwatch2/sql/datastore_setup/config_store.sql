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

/* backends */

insert into pgwatch2.metric(m_name, m_pg_version_from,m_sql)
values (
'backends',
9.0,
$sql$
with sa_snapshot as (
  select * from pg_stat_activity where pid != pg_backend_pid() and not query like 'autovacuum:%'
)
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  (select count(*) from sa_snapshot) as total,
  (select count(*) from sa_snapshot where state = 'active') as active,
  (select count(*) from sa_snapshot where waiting) as waiting,
  (select extract(epoch from (now() - backend_start))::int
    from sa_snapshot order by backend_start limit 1) as longest_session_seconds,
  (select extract(epoch from (now() - xact_start))::int
    from sa_snapshot where xact_start is not null order by xact_start limit 1) as longest_tx_seconds,
  (select extract(epoch from max(now() - query_start))::int
    from sa_snapshot where state = 'active') as longest_query_seconds;
$sql$
);

insert into pgwatch2.metric(m_name, m_pg_version_from,m_sql)
values (
'backends',
9.6,
$sql$
with sa_snapshot as (
  select * from pg_stat_activity where pid != pg_backend_pid() and not query like 'autovacuum:%'
)
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  (select count(*) from sa_snapshot) as total,
  (select count(*) from sa_snapshot where state = 'active') as active,
  (select count(*) from sa_snapshot where wait_event_type is not null) as waiting,
  (select extract(epoch from (now() - backend_start))::int
    from sa_snapshot order by backend_start limit 1) as longest_session_seconds,
  (select extract(epoch from (now() - xact_start))::int
    from sa_snapshot where xact_start is not null order by xact_start limit 1) as longest_tx_seconds,
  (select extract(epoch from max(now() - query_start))::int
    from sa_snapshot where state = 'active') as longest_query_seconds;
$sql$
);

/* bgwriter */

insert into pgwatch2.metric(m_name, m_pg_version_from,m_sql)
values (
'bgwriter',
9.0,
$sql$
select
   (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
   checkpoints_timed,
   checkpoints_req,
   checkpoint_write_time,
   checkpoint_sync_time,
   buffers_checkpoint,
   buffers_clean,
   maxwritten_clean,
   buffers_backend,
   buffers_backend_fsync,
   buffers_alloc
 from
   pg_stat_bgwriter;
$sql$
);

/* cpu_load */

insert into pgwatch2.metric(m_name, m_pg_version_from,m_sql)
values (
'cpu_load',
9.0,
$sql$
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  load_1min,
  load_5min,
  load_15min
from
  public.get_load_average();   -- needs the plpythonu proc from "metric_fetching_helpers" folder
$sql$
);


/* db_stats */

insert into pgwatch2.metric(m_name, m_pg_version_from,m_sql)
values (
'db_stats',
9.0,
$sql$
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  pg_database_size(datname) as size_b,
  numbackends,
  xact_commit,
  xact_rollback,
  blks_read,
  blks_hit,
  tup_returned,
  tup_fetched,
  tup_inserted,
  tup_updated,
  tup_deleted,
  conflicts,
  temp_files,
  temp_bytes,
  deadlocks,
  blk_read_time,
  blk_write_time
from
  pg_stat_database
where
  datname = current_database();
$sql$
);

/* index_stats */

insert into pgwatch2.metric(m_name, m_pg_version_from,m_sql)
values (
'index_stats',
9.0,
$sql$
SELECT
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  schemaname::text as tag_schema,
  indexrelname::text as tag_index_name,
  relname::text as tag_table_name,
  coalesce(idx_scan, 0) as idx_scan,
  coalesce(idx_tup_read, 0) as idx_tup_read,
  coalesce(idx_tup_fetch, 0) as idx_tup_fetch,
  coalesce(pg_relation_size(indexrelid), 0) as index_size_b
FROM
  pg_stat_user_indexes
WHERE
  pg_relation_size(indexrelid) > 1e6    -- >1MB
  AND NOT schemaname like E'pg\\_temp%'
ORDER BY
  schemaname, relname, indexrelname;
$sql$
);


/* kpi */

insert into pgwatch2.metric(m_name, m_pg_version_from,m_sql)
values (
'kpi',
9.0,
$sql$
WITH q_stat_tables AS (
  SELECT * FROM pg_stat_user_tables t
  JOIN pg_class c ON c.oid = t.relid
  WHERE NOT schemaname LIKE E'pg\\_temp%'
  AND c.relpages > (1e7 / 8)    -- >10MB
),
q_stat_activity AS (
  SELECT * FROM pg_stat_activity WHERE pid != pg_backend_pid() AND datname = current_database()
)
SELECT
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  (select pg_xlog_location_diff(pg_current_xlog_location(), '0/0'))::int8 AS wal_location_b,
  numbackends - 1 as numbackends,
  (select count(1) from q_stat_activity where state = 'active') AS active_backends,
  (select count(1) from q_stat_activity where waiting) AS blocked_backends,
  (select round(extract(epoch from now()) - extract(epoch from (select xact_start from q_stat_activity
    where datid = d.datid and not query like 'autovacuum:%' order by xact_start limit 1))))::int AS kpi_oldest_tx_s,
  xact_commit + xact_rollback AS tps,
  xact_commit,
  xact_rollback,
  blks_read,
  blks_hit,
  temp_bytes,
  (select sum(seq_scan) from q_stat_tables) AS seq_scans_on_tbls_gt_10mb,
  tup_inserted,
  tup_updated,
  tup_deleted,
  (select sum(calls) from pg_stat_user_functions where not schemaname like any(array[E'pg\\_%', 'information_schema'])) AS sproc_calls,
  blk_read_time,
  blk_write_time,
  deadlocks
FROM
  pg_stat_database d
WHERE
  datname = current_database();
$sql$
);

/* kpi */

insert into pgwatch2.metric(m_name, m_pg_version_from,m_sql)
values (
'kpi',
9.6,
$sql$
WITH q_stat_tables AS (
  SELECT * FROM pg_stat_user_tables t
  JOIN pg_class c ON c.oid = t.relid
  WHERE NOT schemaname LIKE E'pg\\_temp%'
  AND c.relpages > (1e7 / 8)    -- >10MB
),
q_stat_activity AS (
  SELECT * FROM pg_stat_activity WHERE pid != pg_backend_pid() AND datname = current_database()
)
SELECT
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  (select pg_xlog_location_diff(pg_current_xlog_location(), '0/0'))::int8 AS wal_location_b,
  numbackends - 1 as numbackends,
  (select count(1) from q_stat_activity where state = 'active') AS active_backends,
  (select count(1) from q_stat_activity where wait_event_type is not null) AS blocked_backends,
  (select round(extract(epoch from now()) - extract(epoch from (select xact_start from q_stat_activity
    where datid = d.datid and not query like 'autovacuum:%' order by xact_start limit 1))))::int AS kpi_oldest_tx_s,
  xact_commit + xact_rollback AS tps,
  xact_commit,
  xact_rollback,
  blks_read,
  blks_hit,
  temp_bytes,
  (select sum(seq_scan) from q_stat_tables) AS seq_scans_on_tbls_gt_10mb,
  tup_inserted,
  tup_updated,
  tup_deleted,
  (select sum(calls) from pg_stat_user_functions where not schemaname like any(array[E'pg\\_%', 'information_schema'])) AS sproc_calls,
  blk_read_time,
  blk_write_time,
  deadlocks
FROM
  pg_stat_database d
WHERE
  datname = current_database();
$sql$
);


/* replication */

insert into pgwatch2.metric(m_name, m_pg_version_from,m_sql)
values (
'replication',
9.1,
$sql$
SELECT
  application_name as tag_application_name,
  pg_xlog_location_diff(pg_current_xlog_location(), replay_location)::int8 as lag_b,
  coalesce(client_addr::text, client_hostname) as client_info,
  state
from
  pg_stat_replication;
$sql$
);


/* sproc_stats */

insert into pgwatch2.metric(m_name, m_pg_version_from,m_sql)
values (
'sproc_stats',
9.0,
$sql$
SELECT
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  schemaname::text AS tag_schema,
  funcname::text  AS tag_function_name,
  p.oid as tag_oid, -- for overloaded funcs
  -- TODO compose a siganture and insert annotations when change detected
  --md5(tag_schema||tag_function_name||coalesce(select array_to_string(array(select format_type(t,null) from unnest(coalesce(proallargtypes, proargtypes::oid[])) tt (t)),',')), '')  || coalesce(array_to_string(proargmodes, ','), '')) AS func_signature_md5,
  calls as sp_calls,
  self_time,
  total_time
FROM
  pg_stat_user_functions f
  JOIN
  pg_proc p ON p.oid = f.funcid;
$sql$
);

/* table_io_stats */

insert into pgwatch2.metric(m_name, m_pg_version_from,m_sql)
values (
'table_io_stats',
9.0,
$sql$
SELECT
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  schemaname::text as tag_schema,
  relname::text as tag_table_name,
  heap_blks_read,
  heap_blks_hit,
  idx_blks_read,
  idx_blks_hit,
  toast_blks_read,
  toast_blks_hit,
  tidx_blks_read,
  tidx_blks_hit
FROM
  pg_statio_user_tables
WHERE
  NOT schemaname LIKE E'pg\\_temp%'
  AND (heap_blks_read > 0 OR heap_blks_hit > 0 OR idx_blks_read > 0 OR idx_blks_hit > 0 OR tidx_blks_read > 0 OR tidx_blks_hit > 0);
$sql$
);

/* table_stats */

insert into pgwatch2.metric(m_name, m_pg_version_from,m_sql)
values (
'table_stats',
9.0,
$sql$
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  schemaname::text as tag_schema,
  relname::text as tag_table_name,
  pg_relation_size(relid) as table_size_b,
  pg_total_relation_size(relid) as total_relation_size_b, --TODO add approx as pg_total_relation_size uses locks and can block
  extract(epoch from now() - greatest(last_vacuum, last_autovacuum)) as seconds_since_last_vacuum,
  extract(epoch from now() - greatest(last_analyze, last_autoanalyze)) as seconds_since_last_analyze,
  seq_scan,
  seq_tup_read,
  idx_scan,
  idx_tup_fetch,
  n_tup_ins,
  n_tup_upd,
  n_tup_del,
  n_tup_hot_upd,
  vacuum_count,
  autovacuum_count,
  analyze_count,
  autoanalyze_count
from
  pg_stat_user_tables
where
  not schemaname like E'pg\\_temp%'
  and not exists (select 1 from pg_locks where relation = relid and locktype = 'AccessExclusiveLock' and granted);
$sql$
);

/* wal */

insert into pgwatch2.metric(m_name, m_pg_version_from,m_sql)
values (
'wal',
9.2,
$sql$
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  pg_xlog_location_diff(pg_current_xlog_location(), '0/0')::int8 AS xlog_location_b;
$sql$
);


/* stat_statements */

insert into pgwatch2.metric(m_name, m_pg_version_from,m_sql)
values (
'stat_statements',
9.2,
$sql$
with q_data as (
  select
    (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
    queryid::text as tag_queryid,
    max(ltrim(regexp_replace(query, E'[ \\t\\n\\r]+' , ' ', 'g'))) as tag_query,
    sum(s.calls)::int8 as calls,
    sum(s.total_time)::double precision as total_time,
    sum(shared_blks_hit)::int8 as shared_blks_hit,
    sum(shared_blks_read)::int8 as shared_blks_read,
    sum(shared_blks_written)::int8 as shared_blks_written,
    sum(temp_blks_read)::int8 as temp_blks_read,
    sum(temp_blks_written)::int8 as temp_blks_written,
    sum(blk_read_time)::double precision as blk_read_time,
    sum(blk_write_time)::double precision as blk_write_time
  from
    public.get_stat_statements() s
  where
    calls > 5
    and total_time > 0
    and dbid = (select oid from pg_database where datname = current_database())
    and not upper(s.query) like any (array['DEALLOCATE%', 'SET %', 'RESET %', 'BEGIN%', 'BEGIN;',
      'COMMIT%', 'END%', 'ROLLBACK%', 'SHOW%'])
  group by
    queryid
)
select * from (
  select
    *
  from
    q_data
  where
    total_time > 0
  order by
    total_time desc
  limit 100
) a
union
select * from (
  select
    *
  from
    q_data
  order by
    calls desc
  limit 100
) a
union
select * from (
  select
    *
  from
    q_data
  where
    shared_blks_read > 0
  order by
    shared_blks_read desc
  limit 100
) a
union
select * from (
  select
    *
  from
    q_data
  where
    shared_blks_written > 0
  order by
    shared_blks_written desc
  limit 100
) a
union
select * from (
  select
    *
  from
    q_data
  where
    temp_blks_read > 0
  order by
    temp_blks_read desc
  limit 100
) a
union
select * from (
  select
    *
  from
    q_data
  where
    temp_blks_written > 0
  order by
    temp_blks_written desc
  limit 100
) a;
$sql$
);


/* buffercache_by_db */
insert into pgwatch2.metric(m_name, m_pg_version_from,m_sql)
values (
'buffercache_by_db',
9.2,
$sql$
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  SELECT datname,
  count(*) * 8192
FROM
  pg_buffercache AS b,
  pg_database AS d
WHERE
  d.oid = b.reldatabase
GROUP BY
  1;
$sql$
);

/* buffercache_by_type */
insert into pgwatch2.metric(m_name, m_pg_version_from,m_sql)
values (
'buffercache_by_type',
9.2,
$sql$
select
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
    SELECT       CASE WHEN relkind = 'r' THEN 'Table'   -- TODO all relkinds covered?
                 WHEN relkind = 'i' THEN 'Index'
                 WHEN relkind = 't' THEN 'Toast'
                 WHEN relkind = 'm' THEN 'Materialized view'
                 ELSE 'Other' END,
            count(*) * 8192
    FROM    pg_buffercache AS b, pg_class AS d
    WHERE   d.oid = b.relfilenode
    GROUP BY 1;
$sql$
);


/* pg_stat_ssl */       -- join with backends?
insert into pgwatch2.metric(m_name, m_pg_version_from,m_sql)
values (
'pg_stat_ssl',
9.5,
$sql$
SELECT
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  ssl,
  count(*)
FROM
  pg_stat_ssl AS s,
  pg_stat_activity AS a
WHERE
  a.pid = s.pid
  AND a.datname = current_database()
GROUP BY
  1, 2
$sql$
);


/* pg_stat_database_conflicts */
insert into pgwatch2.metric(m_name, m_pg_version_from,m_sql)
values (
'pg_stat_database_conflicts',
9.2,
$sql$
SELECT
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  confl_tablespace,
  confl_lock,
  confl_snapshot,
  confl_bufferpin,
  confl_deadlock
FROM
  pg_stat_database_conflicts
WHERE
  datname = current_database();
$sql$
);


/* locks - counts only */

insert into pgwatch2.metric(m_name, m_pg_version_from,m_sql)
values (
'locks',
9.0,
$sql$
WITH q_locks AS (
  select
    *
  from
    pg_locks
  where
    pid != pg_backend_pid()
    and database = (select oid from pg_database where datname = current_database())
)
SELECT
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  locktypes AS tag_locktype,
  coalesce((select count(*) FROM q_locks WHERE locktype = locktypes), 0) AS count
FROM
  unnest('{relation, extend, page, tuple, transactionid, virtualxid, object, userlock, advisory}'::text[]) locktypes;
$sql$
);


/* blocking_locks - based on https://wiki.postgresql.org/wiki/Lock_dependency_information.
 not sure if it makes sense though, locks are quite volatile normally */

insert into pgwatch2.metric(m_name, m_pg_version_from,m_sql)
values (
'blocking_locks',
9.2,
$sql$
SELECT
    (extract(epoch from now()) * 1e9)::int8 AS epoch_ns,
    waiting.locktype           AS tag_waiting_locktype,
    waiting_stm.usename        AS tag_waiting_user,
    coalesce(waiting.mode, 'null'::text) AS tag_waiting_mode,
    coalesce(waiting.relation::regclass::text, 'null') AS tag_waiting_table,
    waiting_stm.query          AS waiting_query,
    waiting.pid                AS waiting_pid,
    other.locktype             AS other_locktype,
    other.relation::regclass   AS other_table,
    other_stm.query            AS other_query,
    other.mode                 AS other_mode,
    other.pid                  AS other_pid,
    other_stm.usename          AS other_user
FROM
    pg_catalog.pg_locks AS waiting
JOIN
    pg_catalog.pg_stat_activity AS waiting_stm
    ON (
        waiting_stm.pid = waiting.pid
    )
JOIN
    pg_catalog.pg_locks AS other
    ON (
        (
            waiting."database" = other."database"
        AND waiting.relation  = other.relation
        )
        OR waiting.transactionid = other.transactionid
    )
JOIN
    pg_catalog.pg_stat_activity AS other_stm
    ON (
        other_stm.pid = other.pid
    )
WHERE
    NOT waiting.GRANTED
AND
    waiting.pid <> other.pid
AND
    other.GRANTED
AND
    waiting_stm.datname = current_database();
$sql$
);
