# Available env. variables by components

NB! Some variables influence multiple components. Command line parameters override env. variables (when doing custom deployments).

## Docker image specific

- **NOTESTDB** When set, the config DB won't be added to monitoring as "test". Default: -

## Gatherer daemon

- **PW2_PGHOST** Config DB host. Default: localhost
- **PW2_PGPORT** Config DB port. Default: 5432
- **PW2_PGDATABASE** Config DB name. Default: pgwatch2
- **PW2_PGUSER** Config DB user. Default: pgwatch2
- **PW2_PGPASSWORD** Config DB password. Default: pgwatch2admin
- **PW2_PGSSL** Config DB SSL connection only. Default: False
- **PW2_DATASTORE** Backend for metric storage - [influx|graphite]. Default: influx
- **PW2_VERBOSE** Logging vebosity. By default warning and errors are logged. Use [-v|-vv] to include [info|debug]. Default: -
- **PW2_IHOST** InfluxDB host. Default: localhost
- **PW2_IPORT** InfluxDB port. Default: 8086
- **PW2_IUSER** InfluxDB username. Default: root
- **PW2_IPASSWORD** InfluxDB password. Default: root
- **PW2_IDATABASE** InfluxDB database. Default: pgwatch2
- **PW2_ISSL** Use SSL for InfluxDB. Default: False
- **PW2_IHOST2** Secondary InfluxDB host. Default: localhost
- **PW2_IPORT2** Secondary InfluxDB port. Default: 8086
- **PW2_IUSER2** Secondary InfluxDB username. Default: root
- **PW2_IPASSWORD2** Secondary InfluxDB password. Default: root
- **PW2_IDATABASE2** Secondary InfluxDB database. Default: pgwatch2
- **PW2_ISSL2** Use SSL for Secondary InfluxDB. Default: False
- **PW2_IRETENTIONDAYS** Influx metrics retention period in days. Default: 90
- **PW2_GRAPHITEHOST** Graphite host. Default: -
- **PW2_GRAPHITEPORT** Graphite port. Default: -


## Web UI

- **PW2_WEBHOST** Network interface to listen on. Default: 0.0.0.0
- **PW2_WEBPORT** Port. Default: 8080
- **PW2_WEBSSL** Use HTTPS with self-signed certificates, Default: False
- **PW2_WEBCERT** Enables use of own certificates for custom deployments. Default: '/pgwatch2/self-signed-ssl.pem'
- **PW2_WEBKEY** Enables use of own certificates for custom deployments. Default: '/pgwatch2/self-signed-ssl.key'
- **PW2_WEBCERTCHAIN** Path to certificate chain file for custom deployments. Default: -
- **PW2_WEBNOANONYMOUS** Require user/password to edit data. Default: False
- **PW2_WEBUSER** Admin login. Default: pgwatch2
- **PW2_WEBPASSWORD** Admin password. Default: pgwatch2admin
- **PW2_WEBNOCOMPONENTLOGS** Don't expose Docker component logs. Default: False
- **PW2_VERBOSE** Logging vebosity. By default warning and errors are logged. Use [-v|-vv] to include [info|debug]. Default: -
- **PW2_PGHOST** Config DB host. Default: localhost
- **PW2_PGPORT** Config DB port. Default: 5432
- **PW2_PGDATABASE** Config DB name. Default: pgwatch2
- **PW2_PGUSER** Config DB user. Default: pgwatch2
- **PW2_PGPASSWORD** Config DB password. Default: pgwatch2admin
- **PW2_PGSSL** Config DB SSL connection only. Default: False
- **PW2_IHOST** InfluxDB host. Default: localhost
- **PW2_IPORT** InfluxDB port. Default: 8086
- **PW2_IUSER** InfluxDB username. Default: root
- **PW2_IPASSWORD** InfluxDB password. Default: root
- **PW2_IDATABASE** InfluxDB database. Default: pgwatch2
- **PW2_ISSL** Use SSL for InfluxDB. Default: False
- **PW2_GRAFANA_BASEURL** For linking to Grafana "Query details" dashboard from "Stat_stmt. overview". Default: http://0.0.0.0:3000


## Grafana

- **PW2_GRAFANANOANONYMOUS** Can be set to require login even for viewing dashboards. Default: -
- **PW2_GRAFANAUSER** Administrative user. Default: admin
- **PW2_GRAFANAPASSWORD** Administrative user password. Default: pgwatch2admin
- **PW2_GRAFANASSL** Use SSL. Default: -
- **PW2_GRAFANA_BASEURL** For linking to Grafana "Query details" dashboard from "Stat_stmt. overview". Default: http://0.0.0.0:3000


## InfluxDB

None. NB! InfluxDB built into the pgwatch2 Docker image provides no security (setting up a custom user/password requires
quite some steps), so if this is a concern, the according ports 8086/8088 should just not be exposed, or a custom setup.
