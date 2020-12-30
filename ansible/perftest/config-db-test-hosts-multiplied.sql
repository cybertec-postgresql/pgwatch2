/* To be executed on the Config DB */

SET ROLE TO pgwatch2;

CREATE TABLE pgwatch2.test_hosts(
    id SERIAL PRIMARY KEY,
    host text NOT NULL,
    cpus int NOT NULL DEFAULT 1 -- to use "weights", better machines get more config entries
);

INSERT INTO pgwatch2.test_hosts (host, cpus) VALUES 
('172.31.28.14', 2),
('172.31.20.71', 2),
('172.31.22.229', 2),
('172.31.31.84', 2),
('172.31.22.82', 2),
('172.31.23.128', 2),
('172.31.17.254', 2),
('172.31.26.8', 2),
('172.31.29.134', 2),
('172.31.18.118', 2)
;

CREATE OR REPLACE FUNCTION get_entries_count_by_group(group_id text) RETURNS bigint AS
$$
  select count(*) from pgwatch2.monitored_db where md_group = group_id
$$ LANGUAGE sql;

-- Need to get rid of the "duplicate hosts guard", that's normally desired
DROP INDEX pgwatch2.monitored_db_md_hostname_md_port_md_dbname_md_is_enabled_idx;

INSERT INTO pgwatch2.monitored_db (md_unique_name, md_preset_config_name, md_config, md_hostname, md_port, md_dbname, md_user, md_password, md_group, md_statement_timeout_seconds, md_is_superuser)
SELECT
  'test_host_'||id||'_'|| get_entries_count_by_group(id::text) + 1, 'exhaustive', null, host, '5432', 'postgres', 'pgwatch2', 'perftesting', id, 10, true
FROM
  pgwatch2.test_hosts,
  generate_series(1, cpus * 10) i
  /* 10x multiplier for each host is pretty conservative...but monitor load and re-run the insert gradually until the gatherer or DB nodes choke */
;
