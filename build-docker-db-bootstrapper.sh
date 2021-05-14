#!/bin/bash
docker build --no-cache -t cybertec/pgwatch2-db-bootstrapper:latest -f docker/Dockerfile-db-bootstrapper .
