ALTER TABLE pgwatch2.monitored_db
  ADD md_dbtype text NOT NULL DEFAULT 'postgres'
    CHECK (md_dbtype in ('postgres', 'pgbouncer'));
