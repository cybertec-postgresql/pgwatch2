#!/bin/bash
. common.sh
docker build --no-cache --build-arg ARCH="$ARCH" --build-arg GIT_TIME=`git show -s --format=%cI HEAD` --build-arg GIT_HASH=`git show -s --format=%H HEAD` -t cybertec/pgwatch2:latest .
