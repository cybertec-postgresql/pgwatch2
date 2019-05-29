FROM ubuntu:16.04

RUN apt-get -q update && apt-get -qy install wget git && apt autoremove -y

###
### add pgwatch2 source
###

ADD pgwatch2 /pgwatch2


###
### Install Go and compile the gatherer daemon
###

RUN wget -q -O /tmp/go.tar.gz https://dl.google.com/go/go1.12.5.linux-amd64.tar.gz \
    && tar -C /usr/local -xzf /tmp/go.tar.gz \
    && export PATH=$PATH:/usr/local/go/bin \
    && cd /pgwatch2 && bash build_gatherer.sh \
    && rm -rf /usr/local/go /root/go /tmp/go.tar.gz \
    && chgrp -R 0 /pgwatch2 \
    && chmod -R g=u /pgwatch2

# pgwatch2 internal status endpoint
EXPOSE 8081
# Prometheus metrics scraping port
EXPOSE 9187

USER 10001

ENTRYPOINT ["/pgwatch2/pgwatch2"]
