#!/bin/bash

echo "building build-docker-daemon (log: build-docker-daemon.log)"
./build-docker-daemon.sh &> build-docker-daemon.log
echo "building build-docker-influx (log: build-docker-influx.log)"
./build-docker-influx.sh &> build-docker-influx.log
echo "building build-docker-nonroot (log: build-docker-nonroot.log)"
./build-docker-nonroot.sh &> build-docker-nonroot.log
echo "building build-docker-postgres (log: build-docker-postgres.log)"
./build-docker-postgres.sh &> build-docker-postgres.log

echo "done"
