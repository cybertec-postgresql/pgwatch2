package main

import (
	//"database/sql"
	"fmt"
	"github.com/jmoiron/sqlx"
	_ "github.com/lib/pq"
	"github.com/op/go-logging"
	//"flag"
	//"log"
	"github.com/influxdata/influxdb/client/v2"
	"time"
	//"math/rand"
	"strings"
	"math"
)

var configDb *sqlx.DB
var log = logging.MustGetLogger("datastore_access")

func InitConfigStoreConnection(host, port, dbname, user, password string) {
	var err error

	configDb, err = sqlx.Open("postgres", fmt.Sprintf("host=%s port=%s dbname=%s user=%s password=%s sslmode=prefer",
		host, port, dbname, user, password))
	if err != nil {
		log.Fatal(err)
	}

	err = configDb.Ping()
	if err != nil {
		log.Fatal(err)
	} else {
		log.Info("connect to configDb OK!")
	}
}

func GetAllActiveHosts() {
	var (
		name string
	)
	sql := `
	select
		md_display_name, md_hostname, md_port, md_dbname, md_user, coalesce(md_password, '') as md_password,
	 	md_is_password_encrypted, coalesce(pc_config, md_custom_config)::text as config, now()
	from
		monitored_db
		left join preset_config on pc_name = md_preset_config_name
	where md_is_enabled
	`

	rows, err := configDb.Queryx(sql)
	if err != nil {
		log.Fatal(err)
	}
	defer rows.Close()

	colnames, err := rows.Columns()
	log.Info("colnames:", colnames)

	for rows.Next() {
		//cols, err := rows.SliceScan()
		results := make(map[string]interface{})
		err = rows.MapScan(results)
		//err := rows.Scan(&name)
		if err != nil {
			log.Fatal(err)
		}
		log.Info("cols:", name, results)
	}

	err = rows.Err()
	if err != nil {
		log.Fatal(err)
	}
}


func GetStats() []map[string]interface{} {
	sql := `
select
  pg_database_size(current_database()) as size_b,
  (extract(epoch from now()) * 1e9)::int8 as epoch_n;

	`
	data := make([](map[string]interface{}), 0, 100)

	rows, err := configDb.Queryx(sql)
	if err != nil {
		log.Fatal(err)
	}
	defer rows.Close()

	colnames, err := rows.Columns()
	log.Info("colnames:", colnames)

	for rows.Next() {
		//cols, err := rows.SliceScan()
		results := make(map[string]interface{})
		err = rows.MapScan(results)
		//err := rows.Scan(&name)
		if err != nil {
			log.Fatal(err)
		}
		data = append(data, results)
	}

	err = rows.Err()
	if err != nil {
		log.Fatal(err)
	}
	return data
}

func SendToInflux(data [](map[string]interface{})) {
	//log.Info("data", data)
	log.Info("data[0]", data[0])
	// Make client
	c, err := client.NewHTTPClient(client.HTTPConfig{
		Addr:     "http://localhost:8086",
		Username: "pg",
		Password: "pg",
	})

	if err != nil {
		log.Fatal("Error: ", err)
	}
	defer c.Close()
	// Create a new point batch
	bp, err := client.NewBatchPoints(client.BatchPointsConfig{Database: "pg"})

	if err != nil {
		log.Fatal("Error: ", err)
	}

	for _, dr := range data {
		// Create a point and add to batch
		tags := make(map[string]string)
		fields := make(map[string]interface{})
		//var k string
		//var v interface{}

		for k, v := range dr {
			//log.Info("processing", k, v)
			if strings.HasPrefix(k, "t_") {
				tag := k[2:]
				tags[tag] = fmt.Sprintf("%s", v)
			} else {
				fields[k] = v
			}
		}
		//fields := map[string]interface{}{
		//	"idle":   10.1,
		//	"system": 53.3,
		//	"user":   46.6,
		//}
		//log.Info(tags, fields)
		//return
		pt, err := client.NewPoint("test", tags, fields, time.Now())

		if err != nil {
			log.Fatal("Error: ", err)
		}

		bp.AddPoint(pt)

	}

	// Write the batch
	c.Write(bp)
}

func main() {
	//var logtostderr bool
	//flag.Bool("logtostderr", true, "help message for flagname")
	//flag.Parse()
	logging.SetLevel(logging.INFO, "datastore_access")
	logging.SetFormatter(logging.MustStringFormatter(
		`%{time:15:04:05.000} %{level:.4s} %{shortfunc} ▶ %{message}`,
	))
	log.Info("datastore_access test ...")
	InitConfigStoreConnection("localhost", "5432", "pgwatch2", "krl", "")

	GetAllActiveHosts()

	//data := make([](map[string]interface{}), 0, 10)

	data := GetStats()

	//for i := 0; i < 10 ; i++ {
	//	//data = append(data, map[string]interface{}{"t_host": "cpu1", "query": time.Now().String(), "value": rand.Intn(100)})
	//	data = append(data, map[string]interface{}{"t_host": "cpu1", "query": i, "value": rand.Intn(100)})
	//}

	log.Info("items created:", len(data))
	//log.Info("data created:", data, "\n\n")
	time1 := time.Now()
	SendToInflux(data)
	diff := time.Now().Sub(time1)
	log.Info(float64(diff.Nanoseconds()) / math.Pow10(6), " ms elapsed")
}
