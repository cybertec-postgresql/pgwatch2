module github.com/cybertec-postgresql/pgwatch2

go 1.14

replace github.com/coreos/bbolt => go.etcd.io/bbolt v1.3.5

require (
	github.com/coreos/etcd v3.3.25+incompatible // indirect
	github.com/coreos/go-semver v0.3.0 // indirect
	github.com/coreos/go-systemd v0.0.0-20191104093116-d3cd4ed1dbcf
	github.com/coreos/pkg v0.0.0-20180928190104-399ea9e2e55f // indirect
	github.com/hashicorp/consul/api v1.6.0
	github.com/influxdata/influxdb1-client v0.0.0-20200827194710-b269163b24ab
	github.com/jessevdk/go-flags v1.4.0
	github.com/jmoiron/sqlx v1.2.0
	github.com/lib/pq v1.8.0
	github.com/marpaia/graphite-golang v0.0.0-20190519024811-caf161d2c2b1
	github.com/op/go-logging v0.0.0-20160315200505-970db520ece7
	github.com/prometheus/client_golang v1.7.1
	github.com/samuel/go-zookeeper v0.0.0-20200724154423-2164a8ac840e
	github.com/shirou/gopsutil/v3 v3.20.12 // indirect
	github.com/shopspring/decimal v1.2.0
	go.etcd.io/etcd v3.3.25+incompatible
	golang.org/x/crypto v0.0.0-20200820211705-5c72a883971a
	gopkg.in/yaml.v2 v2.3.0
)
