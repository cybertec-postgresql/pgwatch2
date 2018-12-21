insert into data_source (org_id, version, type, name, access, url,
  password, "user", database, basic_auth, is_default, json_data, created, updated
  ) values (
  1, 0, 'postgres', 'pg-metrics', 'proxy', 'localhost:5432',
  'pgwatch2admin', 'pgwatch2', 'pgwatch2_metrics', 'f', 't', '{"postgresVersion":1000,"sslmode":"disable","timescaledb":false}', now(), now()
  );
