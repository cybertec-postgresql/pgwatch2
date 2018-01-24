FROM debian:jessie

###
# non-root adjustments to https://github.com/grafana/grafana-docker
###

ARG DOWNLOAD_URL

RUN apt-get update && \
    apt-get -y --no-install-recommends install libfontconfig curl ca-certificates && \
    apt-get clean && \
    curl ${DOWNLOAD_URL} > /tmp/grafana.deb && \
    dpkg -i /tmp/grafana.deb && \
    rm /tmp/grafana.deb && \
    apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/*

RUN chgrp -R 0 /var/lib/grafana /var/log/grafana /etc/grafana /usr/share/grafana /etc/passwd \
    && chmod -R g=u /var/lib/grafana /var/log/grafana /etc/grafana/ /usr/share/grafana /etc/passwd

VOLUME ["/var/lib/grafana", "/var/log/grafana", "/etc/grafana"]

EXPOSE 3000

COPY grafana-run.sh /run.sh

USER 10001

ENTRYPOINT ["/run.sh"]
