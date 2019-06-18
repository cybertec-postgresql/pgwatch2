#!/bin/bash

set -e

./smoke_test_docker_image.sh influx cybertec/pgwatch2:latest
./smoke_test_docker_image.sh influx cybertec/pgwatch2-nonroot:latest
./smoke_test_docker_image.sh pg cybertec/pgwatch2-postgres:latest
