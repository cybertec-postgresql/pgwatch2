Dashboarding and alerting
=========================

# Screenshot of the "DB overview" dashboard
!["DB overview" dashboard](https://github.com/cybertec-postgresql/pgwatch2/raw/master/screenshots/overview.png)

More screenshots [here](https://github.com/cybertec-postgresql/pgwatch2/tree/master/screenshots)

Alerting
--------

Alerting is very conveniently (point-and-click style) provided by Grafana - see [here](http://docs.grafana.org/alerting/rules/)
for documentation. All most popular notification services are supported. A hint - currently you can set alerts only on Graph
panels and there must be no variables used in the query so you cannot use most of the pre-created pgwatch2 graphs. There's s template
named "Alert Template" though to give you some ideas on what to alert on.

If more complex scenarios/check conditions are required TICK stack and Kapacitor can be easily integrated - see
[here](https://www.influxdata.com/time-series-platform/kapacitor/) for more details.