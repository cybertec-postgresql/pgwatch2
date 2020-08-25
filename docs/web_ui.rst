The Admin Web UI
================

In the centrally managed (config DB based) mode, for easy configuration changes (adding databases to monitoring, adding
metrics) there is a small Python Web application bundled (exposed on Docker port 8080), making use of the CherryPy
Web-framework. For mass changes one could technically also log into the configuration database and change the tables in
the "pgwatch2" schema directly. Besides managing the metrics gathering configurations, the two other useful features for
the Web UI would be the possibility to look at the logs of the single components (when using Docker) and at the "Stat
Statements Overview" page, which will e.g. enable finding out the query with the slowest average runtime for a time period.

By default the Web UI is not secured. If some security is needed then the following env. variables can be used to enforce
password protection - PW2_WEBNOANONYMOUS, PW2_WEBUSER, PW2_WEBPASSWORD.

By default also the Docker component logs (Postgres, Influx, Grafana, Go daemon, Web UI itself) are exposed via the "/logs"
endpoint. If this is not wanted set the PW2_WEBNOCOMPONENTLOGS env. variable.

Note that if the "/logs" endpoint is wanted also in the custom setup mode (non-docker) then then some actual code changes
are needed to specify where logs of all components are situated - see top of the pgwatch2.py file for that.
