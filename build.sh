#!/bin/bash

pushd pgwatch2
go build pgwatch2.go
popd

docker build .

