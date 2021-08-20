#!/bin/bash
. common.sh
docker build --no-cache --build-arg ARCH="$ARCH" -t cybertec/pgwatch2-db-bootstrapper:latest -f docker/Dockerfile-db-bootstrapper .
