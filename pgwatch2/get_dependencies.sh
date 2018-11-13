#!/bin/bash

go_on_path=$(which go)
if [ -z "$go_on_path" ] ; then
    export PATH=$PATH:/usr/local/go/bin
fi

echo "getting project dependencies..."
go get -u github.com/lib/pq
go get -u github.com/op/go-logging
go get -u github.com/jmoiron/sqlx
go get -u github.com/influxdata/influxdb/client/v2
go get -u github.com/jessevdk/go-flags
go get -u github.com/marpaia/graphite-golang
go get -u github.com/shopspring/decimal
go get -u gopkg.in/yaml.v2
go get -u github.com/coreos/go-systemd/daemon
