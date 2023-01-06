#!/bin/bash

echo "building build-docker-daemon (log: build-docker-daemon.log)"
./build-docker-daemon.sh &> build-docker-daemon.log
if [ $? -ne 0 ]; then
  echo "failed. see log for details"
else
  echo "ok"
fi

echo "building build-docker-influx (log: build-docker-influx.log)"
./build-docker-influx.sh &> build-docker-influx.log
if [ $? -ne 0 ]; then
  echo "failed. see log for details"
else
  echo "ok"
fi

echo "building build-docker-nonroot (log: build-docker-nonroot.log)"
./build-docker-nonroot.sh &> build-docker-nonroot.log
if [ $? -ne 0 ]; then
  echo "failed. see log for details"
else
  echo "ok"
fi

echo "building build-docker-postgres (log: build-docker-postgres.log)"
./build-docker-postgres.sh &> build-docker-postgres.log
if [ $? -ne 0 ]; then
  echo "failed. see log for details"
else
  echo "ok"
fi

echo "building build-docker-timescale (log: build-docker-timescale.log)"
./build-docker-timescale.sh &> build-docker-timescale.log
if [ $? -ne 0 ]; then
  echo "failed. see log for details"
else
  echo "ok"
fi

echo "building build-docker-db-bootstrapper (log: build-docker-db-bootstrapper.log)"
./build-docker-db-bootstrapper.sh &> build-docker-db-bootstrapper.log
if [ $? -ne 0 ]; then
  echo "failed. see log for details"
else
  echo "ok"
fi

echo "done"
