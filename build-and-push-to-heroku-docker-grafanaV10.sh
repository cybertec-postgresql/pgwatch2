#!/bin/bash

: "${HK_APP_NAME:=ab-cr-pgwatch2-grafana-v1120}"
: "${HK_PROC_TYPE:=web}"
: "${DOCKER_FILE:=docker/Dockerfile-grafanaV10-heroku}"

heroku container:login && \
docker build -t registry.heroku.com/${HK_APP_NAME}/${HK_PROC_TYPE} -f ${DOCKER_FILE} . && \
docker push registry.heroku.com/${HK_APP_NAME}/${HK_PROC_TYPE} && \
heroku container:release ${HK_PROC_TYPE} -a ${HK_APP_NAME}