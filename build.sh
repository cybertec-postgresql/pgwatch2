#!/bin/bash

pushd pgwatch2
./get_dependencies.sh
go build pgwatch2.go
popd

docker build .

