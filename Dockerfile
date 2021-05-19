FROM golang:1.16.3

# For showing Git version via 'pgwatch2 --version'
ARG GIT_HASH
ARG GIT_TIME
ENV GIT_HASH=${GIT_HASH}
ENV GIT_TIME=${GIT_TIME}

ADD pgwatch2 /pgwatch2
RUN cd /pgwatch2 && bash build_gatherer.sh


FROM ubuntu:16.04

RUN apt-get -q update \
    && apt-get -qy install wget apt-transport-https vim git postgresql postgresql-plpython3-9.5 postgresql-plpython-9.5 libfontconfig python3-pip python-pip libssl-dev libpq-dev \
    && pip install -U "pip < 21.0" && pip3 install -U "pip < 21.0" \
    && locale-gen "en_US.UTF-8" && apt autoremove -y \
    && pg_dropcluster 9.5 main ; pg_createcluster --locale en_US.UTF-8 9.5 main \
    && echo "include = 'pgwatch_postgresql.conf'" >> /etc/postgresql/9.5/main/postgresql.conf

### Download and install external components
# Grafana [https://grafana.com/grafana/download]
#   latest ver.: curl -so- https://api.github.com/repos/grafana/grafana/tags | grep -Eo '"v[0-9\.]+"' | grep -Eo '[0-9\.]+' | sort -nr | head -1
# Influxdb [https://portal.influxdata.com/downloads]
#   latest ver.: curl -so- https://api.github.com/repos/influxdata/influxdb/tags | grep -Eo '"v[0-9\.]+"' | grep -Eo '[0-9\.]+' | sort -nr | head -1

RUN wget -q -O grafana.deb https://dl.grafana.com/oss/release/grafana_6.7.6_amd64.deb \
    && wget -q -O - https://dl.influxdata.com/influxdb/releases/influxdb_1.8.5_amd64.deb > influxdb_amd64.deb \
    && dpkg -i grafana.deb && rm grafana.deb \
    && dpkg -i influxdb_amd64.deb && rm influxdb_amd64.deb \
    && sed -i 's/\# query-log-enabled = true/query-log-enabled = false/' /etc/influxdb/influxdb.conf \
    && sed -i 's/\# \[monitor\]/\[monitor\]/' /etc/influxdb/influxdb.conf \
    && sed -i 's/\# store-enabled = true/store-enabled = false/' /etc/influxdb/influxdb.conf \
    && sed -i 's/\# \[http\]/\[http\]/' /etc/influxdb/influxdb.conf \
    && sed -i '0,/\# log-enabled = true/{s/\# log-enabled = true/log-enabled = false/}' /etc/influxdb/influxdb.conf \
    && sed -i 's/\# index-version = \"inmem\"/index-version = \"tsi1\"/' /etc/influxdb/influxdb.conf \
    && sed -i 's/\# bind-address = \"127.0.0.1:8088\"/bind-address = \":8088\"/' /etc/influxdb/influxdb.conf \
    && sed -i 's/\# wal-fsync-delay = \"0s\"/wal-fsync-delay = \"500ms\"/' /etc/influxdb/influxdb.conf \
    && pip3 install supervisor pyyaml && mkdir /var/log/supervisor


# Add pgwatch2 sources
ADD pgwatch2 /pgwatch2
# Copy over the compiled gatherer
COPY --from=0 /pgwatch2/pgwatch2 /pgwatch2
ADD webpy /pgwatch2/webpy

# For showing Git version via Web UI :8080/versions
ARG GIT_HASH
ARG GIT_TIME
ENV GIT_HASH=${GIT_HASH}
ENV GIT_TIME=${GIT_TIME}
# For showing all component versions via :8080/versions. Assuming project is cloned from Github here
RUN echo "${GIT_HASH} ${GIT_TIME}" > /pgwatch2/build_git_version.txt

# Grafana config customizations, Web UI requirements, compilation of the Go gatherer
RUN cp /pgwatch2/bootstrap/grafana_custom_config.ini /etc/grafana/grafana.ini \
    && pip3 install -r /pgwatch2/webpy/requirements_influx_metrics.txt \
    && pip2 install psutil \
    && grafana-cli plugins install savantly-heatmap-panel

# both Python 2 and 3 only there for the "transition" period, to not brake some people upgrading to a newer image.
# at some point Python2 should be dropped completely.
RUN pip3 install psutil

ADD grafana_dashboards /pgwatch2/grafana_dashboards

# Set up supervisord [https://docs.docker.com/engine/admin/using_supervisord/]
COPY supervisord.conf /etc/supervisor/supervisord.conf

# Postgres (ver 9.5) config tuning
# NB! When security is a concern one should definitely alter "pgwatch2" password in change_pw.sql and maybe modify pg_hba.conf accordingly
COPY postgresql.conf /etc/postgresql/9.5/main/pgwatch_postgresql.conf
COPY pg_hba.conf /etc/postgresql/9.5/main/pg_hba.conf
COPY docker-launcher.sh postgresql.conf pg_hba.conf /pgwatch2/

ENV PW2_AES_GCM_KEYPHRASE_FILE /pgwatch2/persistent-config/default-password-encryption-key.txt

# Admin UI for configuring servers to be monitored
EXPOSE 8080
# Gatherer healthcheck port / metric statistics (JSON)
EXPOSE 8081
# Postgres DB holding the pgwatch2 config DB
EXPOSE 5432
# Grafana UI
EXPOSE 3000
# InfluxDB API
EXPOSE 8086
# InfluxDB backup port
EXPOSE 8088
# Prometheus scraping port
EXPOSE 9187

### Volumes for easier updating to newer to newer pgwatch2 containers
### NB! Backwards compatibility is not 100% guaranteed (e.g. InfluxDB has changed index storage format) so a backup
### using traditional means is still recommended before updating - see "Updating to a newer Docker version" from README

VOLUME /pgwatch2/persistent-config
VOLUME /var/lib/postgresql
VOLUME /var/lib/influxdb
VOLUME /var/lib/grafana

CMD ["/pgwatch2/docker-launcher.sh"]
