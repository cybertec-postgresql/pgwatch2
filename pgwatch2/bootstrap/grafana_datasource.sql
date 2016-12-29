insert into data_source (org_id, version, type, name, access, url,
  password, "user", database, basic_auth, is_default, json_data, created, updated
  ) values (
  1, 0, 'influxdb', 'Influx', 'proxy', 'http://localhost:8086',
  'root', 'root', 'pgwatch2', 'f', 't', '{}', now(), now()
  );
