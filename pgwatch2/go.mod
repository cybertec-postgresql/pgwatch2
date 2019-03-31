module "https://github.com/cybertec-postgresql/pgwatch2"

go 1.12

require (
	github.com/coreos/go-systemd v0.0.0-20190321100706-95778dfbb74e
	github.com/influxdata/influxdb1-client v0.0.0-20190124200505-16c852ea613f
	github.com/jessevdk/go-flags v1.4.0
	github.com/jmoiron/sqlx v1.2.0
	github.com/lib/pq v1.0.0
	github.com/marpaia/graphite-golang v0.0.0-20171231172105-134b9af18cf3
	github.com/op/go-logging v0.0.0-20160315200505-970db520ece7
	github.com/shopspring/decimal v0.0.0-20180709203117-cd690d0c9e24
	golang.org/x/crypto v0.0.0-20190325154230-a5d413f7728c
	gopkg.in/yaml.v2 v2.2.2
)
