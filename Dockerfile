FROM ubuntu:16.04

RUN apt-get -q update && apt-get -qy install curl wget vim apt-transport-https supervisor postgresql postgresql-plpython-9.5

ADD pgwatch2 /pgwatch2

### Set up supervisord [https://docs.docker.com/engine/admin/using_supervisord/]
RUN mkdir -p /var/log/supervisor
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
RUN chmod +x /pgwatch2/bootstrap/set_up_grafana_dashboards.sh

### Install Grafana [http://grafana.org/]
RUN curl https://packagecloud.io/gpg.key | apt-key add -
RUN echo "deb https://packagecloud.io/grafana/stable/debian/ jessie main" >> /etc/apt/sources.list
RUN apt-get -q update && apt-get -qy install grafana
RUN cp /pgwatch2/bootstrap/grafana_custom_config.ini /etc/grafana/grafana.ini

EXPOSE 3000

###  Influxdb [https://influxdb.com/download/index.html] # taking the latest "stable" by default
RUN wget -q -O - Gsq https://api.github.com/repos/influxdb/influxdb/tags | grep -Eo '"v[0-9\.]+"' | grep -Eo '[0-9\.]+' | head -1 > influx_ver.txt
RUN echo "downloading InfluxDB ver:" && cat influx_ver.txt
RUN wget -q -O - "https://dl.influxdata.com/influxdb/releases/influxdb_$(cat influx_ver.txt)_amd64.deb" > influxdb_amd64.deb
RUN dpkg -i influxdb_amd64.deb

RUN sed -i 's/\# query-log-enabled = true/query-log-enabled = false/' /etc/influxdb/influxdb.conf
RUN sed -i 's/\# \[monitor\]/\[monitor\]/' /etc/influxdb/influxdb.conf
RUN sed -i 's/\# store-enabled = true/store-enabled = false/' /etc/influxdb/influxdb.conf
RUN sed -i 's/\# \[http\]/\[http\]/' /etc/influxdb/influxdb.conf
RUN sed -i '0,/\# log-enabled = true/{s/\# log-enabled = true/log-enabled = false/}' /etc/influxdb/influxdb.conf
# FYI admin UI  Deprecated as of 1.1.0
RUN sed -Ei 's/^(\[admin\])/\1\n  enabled=true/' /etc/influxdb/influxdb.conf

EXPOSE 8083
EXPOSE 8086
# port for taking Influx backups
EXPOSE 8088


### Postgres (ver 9.5) config tuning
COPY postgresql.conf /etc/postgresql/9.5/main/pgwatch_postgresql.conf
COPY pg_hba.conf /etc/postgresql/9.5/main/pg_hba.conf

RUN echo "include = 'pgwatch_postgresql.conf'" >> /etc/postgresql/9.5/main/postgresql.conf
# NB! When security is a concern one should definitely alter "postgres" password in change_pw.sql and maybe modify pg_hba.conf accordingly

USER postgres
RUN /usr/lib/postgresql/9.5/bin/postgres --single -j -D /var/lib/postgresql/9.5/main -c config_file=/etc/postgresql/9.5/main/postgresql.conf postgres </pgwatch2/bootstrap/change_pw.sql
RUN /usr/lib/postgresql/9.5/bin/postgres --single -j -D /var/lib/postgresql/9.5/main -c config_file=/etc/postgresql/9.5/main/postgresql.conf postgres </pgwatch2/bootstrap/create_db_pgwatch.sql
RUN /usr/lib/postgresql/9.5/bin/postgres --single -j -D /var/lib/postgresql/9.5/main -c config_file=/etc/postgresql/9.5/main/postgresql.conf postgres </pgwatch2/bootstrap/create_db_grafana.sql
RUN /usr/lib/postgresql/9.5/bin/postgres --single -j -D /var/lib/postgresql/9.5/main -c config_file=/etc/postgresql/9.5/main/postgresql.conf pgwatch2 </pgwatch2/sql/datastore_setup/config_store.sql
RUN /usr/lib/postgresql/9.5/bin/postgres --single -j -D /var/lib/postgresql/9.5/main -c config_file=/etc/postgresql/9.5/main/postgresql.conf pgwatch2 </pgwatch2/sql/datastore_setup/metric_definitions.sql
RUN /usr/lib/postgresql/9.5/bin/postgres --single -j -D /var/lib/postgresql/9.5/main -c config_file=/etc/postgresql/9.5/main/postgresql.conf pgwatch2 </pgwatch2/sql/metric_fetching_helpers/cpu_load_plpythonu.sql
RUN /usr/lib/postgresql/9.5/bin/postgres --single -j -D /var/lib/postgresql/9.5/main -c config_file=/etc/postgresql/9.5/main/postgresql.conf pgwatch2 </pgwatch2/sql/metric_fetching_helpers/stat_statements_wrapper.sql

EXPOSE 5432


USER root

# Web UI
ADD webpy /pgwatch2/webpy
RUN apt-get -qy install python3-pip postgresql-server-dev-9.5
RUN pip3 install -r /pgwatch2/webpy/requirements.txt

EXPOSE 8080

ADD grafana_dashboards /pgwatch2/grafana_dashboards

COPY build_git_version.txt /pgwatch2/build_git_version.txt

CMD ["/usr/bin/supervisord"]
