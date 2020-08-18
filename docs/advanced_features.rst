## Patroni usage

When 'patroni' is selected for "DB type" then the usual host/port fields should be left empty ("dbname" still filled if only
one database is to be monitored) and instead "Host config" JSON field should be filled with DCS address, type and scope
(cluster) name) information. A sample config looks like:

```
{
"dcs_type": "etcd",
"dcs_endpoints": ["http://127.0.0.1:2379"],
"scope": "batman",
"namespace": "/service/"
}
```

For etcd also username, password, ca_file, cert_file, key_file optional parameters can be defined - other DCS systems
are currently supported only without authentication.

Also if you don't use the replicas actively for queries then it might make sense to decrease the volume of gathered
metrics and to disable the monitoring of standby-s with the "Master mode only?" checkbox.

## Log parsing feature

As of v1.7.0 the metrics collector daemon, when installed on the DB server (preferably with YAML config), has capabilities
to parse the database server logs. Out-of-the-box it will though only work when logs are written in CVSLOG format. For other
formats user needs to specify a regex that parses out as a named group following fields: database_name, error_severity.
See [here](https://github.com/cybertec-postgresql/pgwatch2/blob/master/pgwatch2/logparse.go#L27) for an example regex.

NB! Note that only the event counts are stored, by severity, for the monitored DB and for the whole instance - no error
texts or username infos! The metric name to enable log parsing is "server_log_event_counts". Also note that for auto-detection
of log destination / setting to work the monitoring user needs superuser / pg_monitor rights - if this is not possible
then log settings need to be specified manually under "Host config" as seen for example [here](https://github.com/cybertec-postgresql/pgwatch2/blob/master/pgwatch2/config/instances.yaml).

### Sample configuration if not using CSVLOG

Assuming Debian / Ubuntu default log_line_prefix:

```
log_line_prefix = '%m [%p] %q%u@%d '
```

```
# YAML config
...
  logs_match_regex: '^(?P<log_time>.*) \[(?P<process_id>\d+)\] (?P<user_name>.*)@(?P<database_name>.*?) (?P<error_severity>.*?): '
...
```