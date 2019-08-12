#!/bin/bash

go_on_path=$(which go)
if [ -z "$go_on_path" ] ; then
    export PATH=$PATH:/usr/local/go/bin
fi

./get_dependencies.sh

echo "running 'go build pgwatch2.go' ..."
go build -ldflags "-X 'main.GitVersionHash=`git show -s --format=\"%H (%ci)\" HEAD`'" pgwatch2.go prom.go patroni.go
