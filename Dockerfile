FROM ubuntu:16.04

RUN apt-get -q update && apt-get -qy install wget apt-transport-https vim git supervisor postgresql postgresql-plpython-9.5 libfontconfig python3-pip \
    && mkdir -p /var/log/supervisor \
    && locale-gen "en_US.UTF-8" \
    && pg_dropcluster 9.5 main ; pg_createcluster --locale en_US.UTF-8 9.5 main

###
### Install Go
###

RUN wget -q https://storage.googleapis.com/golang/go1.9.2.linux-amd64.tar.gz \
    && tar -C /usr/local -xzf go1.9.2.linux-amd64.tar.gz \
    && rm go1.9.2.linux-amd64.tar.gz \
    && export PATH=$PATH:/usr/local/go/bin \
    && echo 'export PATH=$PATH:/usr/local/go/bin' >> /root/.bashrc

###
### Install Grafana [http://grafana.org/]
###
RUN wget -q -O grafana.deb https://s3-us-west-2.amazonaws.com/grafana-releases/release/grafana_4.6.1_amd64.deb && dpkg -i grafana.deb && rm grafana.deb

###
###  Influxdb [https://influxdb.com/download/index.html]
###

# use following to get lastest version nr:
# curl curl -so- https://api.github.com/repositories/13124802/tags | grep -Eo '"v[0-9\.]+"' | grep -Eo '[0-9\.]+' | head -1 | grep -Eo '"v[0-9\.]+"' | grep -Eo '[0-9\.]+' | head -1
RUN wget -q -O - "https://dl.influxdata.com/influxdb/releases/influxdb_1.3.7_amd64.deb" > influxdb_amd64.deb && dpkg -i influxdb_amd64.deb && rm influxdb_amd64.deb


###
### add pgwatch2 source and configure installed components
###

ADD pgwatch2 /pgwatch2

# Set up supervisord [https://docs.docker.com/engine/admin/using_supervisord/]
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Influx
RUN sed -i 's/\# query-log-enabled = true/query-log-enabled = false/' /etc/influxdb/influxdb.conf \
    && sed -i 's/\# \[monitor\]/\[monitor\]/' /etc/influxdb/influxdb.conf \
    && sed -i 's/\# store-enabled = true/store-enabled = false/' /etc/influxdb/influxdb.conf \
    && sed -i 's/\# \[http\]/\[http\]/' /etc/influxdb/influxdb.conf \
    && sed -i '0,/\# log-enabled = true/{s/\# log-enabled = true/log-enabled = false/}' /etc/influxdb/influxdb.conf

# Grafana
RUN cp /pgwatch2/bootstrap/grafana_custom_config.ini /etc/grafana/grafana.ini

# Postgres (ver 9.5) config tuning
# NB! When security is a concern one should definitely alter "postgres" password in change_pw.sql and maybe modify pg_hba.conf accordingly
COPY postgresql.conf /etc/postgresql/9.5/main/pgwatch_postgresql.conf
COPY pg_hba.conf /etc/postgresql/9.5/main/pg_hba.conf

USER postgres

RUN echo "include = 'pgwatch_postgresql.conf'" >> /etc/postgresql/9.5/main/postgresql.conf \
    && /usr/lib/postgresql/9.5/bin/postgres --single -j -D /var/lib/postgresql/9.5/main -c config_file=/etc/postgresql/9.5/main/postgresql.conf postgres </pgwatch2/bootstrap/change_pw.sql \
    && /usr/lib/postgresql/9.5/bin/postgres --single -j -D /var/lib/postgresql/9.5/main -c config_file=/etc/postgresql/9.5/main/postgresql.conf postgres </pgwatch2/bootstrap/create_db_pgwatch.sql \
    && /usr/lib/postgresql/9.5/bin/postgres --single -j -D /var/lib/postgresql/9.5/main -c config_file=/etc/postgresql/9.5/main/postgresql.conf postgres </pgwatch2/bootstrap/create_db_grafana.sql \
    && /usr/lib/postgresql/9.5/bin/postgres --single -j -D /var/lib/postgresql/9.5/main -c config_file=/etc/postgresql/9.5/main/postgresql.conf pgwatch2 </pgwatch2/sql/datastore_setup/config_store.sql \
    && /usr/lib/postgresql/9.5/bin/postgres --single -j -D /var/lib/postgresql/9.5/main -c config_file=/etc/postgresql/9.5/main/postgresql.conf pgwatch2 </pgwatch2/sql/datastore_setup/metric_definitions.sql \
    && /usr/lib/postgresql/9.5/bin/postgres --single -j -D /var/lib/postgresql/9.5/main -c config_file=/etc/postgresql/9.5/main/postgresql.conf pgwatch2 </pgwatch2/sql/metric_fetching_helpers/cpu_load_plpythonu.sql \
    && /usr/lib/postgresql/9.5/bin/postgres --single -j -D /var/lib/postgresql/9.5/main -c config_file=/etc/postgresql/9.5/main/postgresql.conf pgwatch2 </pgwatch2/sql/metric_fetching_helpers/stat_statements_wrapper.sql \
    && /usr/lib/postgresql/9.5/bin/postgres --single -j -D /var/lib/postgresql/9.5/main -c config_file=/etc/postgresql/9.5/main/postgresql.conf pgwatch2 </pgwatch2/sql/metric_fetching_helpers/table_bloat_approx.sql

USER root

# Get Web UI requirements and compile the Go gatherer
ADD webpy /pgwatch2/webpy
RUN pip3 install -r /pgwatch2/webpy/requirements.txt && cd /pgwatch2 && bash build_gatherer.sh

ADD grafana_dashboards /pgwatch2/grafana_dashboards

# For showing all component versions via :8080/versions. Assuming project is cloned from Github here
COPY .git/refs/heads/master /pgwatch2/build_git_version.txt


# Admin UI for configuring servers to be monitored
EXPOSE 8080
# Postgres DB holding the pgwatch2 config DB
EXPOSE 5432
# Grafana UI
EXPOSE 3000
# InfluxDB API
EXPOSE 8086
# port for taking Influx backups
EXPOSE 8088


CMD ["/usr/bin/supervisord"]
