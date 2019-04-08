package main

import (
	"fmt"
	"net/http"
	"reflect"
	"strconv"
	"strings"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

type Exporter struct {
	lastScrapeErrors                  prometheus.Gauge
	totalScrapes, totalScrapeFailures prometheus.Counter
}

func NewExporter() (*Exporter, error) {
	return &Exporter{
		lastScrapeErrors: prometheus.NewGauge(prometheus.GaugeOpts{
			Namespace: opts.PrometheusNamespace,
			Name:      "exporter_last_scrape_errors",
			Help:      "Last scrape error count for all monitored hosts / metrics",
		}),
		totalScrapes: prometheus.NewCounter(prometheus.CounterOpts{
			Namespace: opts.PrometheusNamespace,
			Name:      "exporter_total_scrapes",
			Help:      "Total scrape attempts.",
		}),
		totalScrapeFailures: prometheus.NewCounter(prometheus.CounterOpts{
			Namespace: opts.PrometheusNamespace,
			Name:      "exporter_total_scrape_failures",
			Help:      "Number of errors while executing metric queries",
		}),
	}, nil
}

// Not really needed for scraping to work
func (e *Exporter) Describe(ch chan<- *prometheus.Desc) {
}

func (e *Exporter) Collect(ch chan<- prometheus.Metric) {
	var lastScrapeErrors float64

	e.totalScrapes.Add(1)
	ch <- e.totalScrapes

	monitoredDatabases := getMonitoredDatabasesSnapshot()
	if len(monitoredDatabases) == 0 {
		log.Warning("No dbs configured for monitoring. Check config")
		ch <- e.totalScrapeFailures
		e.lastScrapeErrors.Set(0)
		ch <- e.lastScrapeErrors
		return
	}
	for name, md := range monitoredDatabases {
		for metric, interval := range md.Metrics {
			if interval > 0 {
				log.Debugf("scraping [%s:%s]...", md.DBUniqueName, metric)
				metricStoreMessages, err := FetchMetrics( // TODO conn pooling
					MetricFetchMessage{DBUniqueName: name, MetricName: metric, DBType: md.DBType},
					nil,
					nil,
					CONTEXT_PROMETHEUS_SCRAPE)
				if err != nil {
					log.Errorf("failed to scrape [%s:%s]: %v", name, metric, err)
					e.totalScrapeFailures.Add(1)
					lastScrapeErrors++
					continue
				}
				if len(metricStoreMessages) > 0 {
					promMetrics := MetricStoreMessageToPromMetrics(metricStoreMessages[0])
					for _, pm := range promMetrics { // collect & send later in batch? capMetricChan = 1000 limit in prometheus code
						ch <- pm
					}
				}
			}
		}
	}
	ch <- e.totalScrapeFailures
	e.lastScrapeErrors.Set(lastScrapeErrors)
	ch <- e.lastScrapeErrors
}

func getMonitoredDatabasesSnapshot() map[string]MonitoredDatabase {
	mdSnap := make(map[string]MonitoredDatabase)

	if monitored_db_cache != nil {
		monitored_db_cache_lock.RLock()
		defer monitored_db_cache_lock.RUnlock()

		for _, row := range monitored_db_cache {
			mdSnap[row.DBUniqueName] = row
		}
	}

	return mdSnap
}

func MetricStoreMessageToPromMetrics(msg MetricStoreMessage) []prometheus.Metric {
	promMetrics := make([]prometheus.Metric, 0)

	var epoch_time time.Time
	var epoch_ns int64

	if len(msg.Data) == 0 {
		return promMetrics
	}

	epoch_ns, ok := (msg.Data[0][EPOCH_COLUMN_NAME]).(int64)
	if !ok {
		if msg.MetricName != "pgbouncer_stats" {
			log.Warning("No timestamp_ns found, (gatherer) server time will be used. measurement:", msg.MetricName)
		}
		epoch_time = time.Now()
	} else {
		epoch_time = time.Unix(0, epoch_ns)
	}

	for _, dr := range msg.Data {
		labels := make(map[string]string)
		fields := make(map[string]float64)
		labels["dbname"] = msg.DBUniqueName

		for k, v := range dr {
			if v == nil || v == "" || k == EPOCH_COLUMN_NAME {
				continue // not storing NULLs. epoch checked/assigned once
			}

			if strings.HasPrefix(k, "tag_") {
				tag := k[4:]
				labels[tag] = fmt.Sprintf("%v", v)
			} else {
				dataType := reflect.TypeOf(v).String()
				if dataType == "float64" || dataType == "float32" || dataType == "int64" || dataType == "int32" || dataType == "int" {
					f, err := strconv.ParseFloat(fmt.Sprintf("%v", v), 64)
					if err != nil {
						log.Debugf("Skipping scraping column %s of [%s:%s]: %v", k, msg.DBUniqueName, msg.MetricName, err)
					}
					fields[k] = f
				} else if dataType == "bool" {
					if v.(bool) {
						fields[k] = 1
					} else {
						fields[k] = 0
					}
				} else {
					log.Debugf("Skipping scraping column %s of [%s:%s], unsupported datatype: %s", k, msg.DBUniqueName, msg.MetricName, dataType)
					continue
				}
			}
		}
		if msg.CustomTags != nil {
			for k, v := range msg.CustomTags {
				labels[k] = fmt.Sprintf("%v", v)
			}
		}

		label_keys := make([]string, 0)
		label_values := make([]string, 0)
		for k, v := range labels {
			label_keys = append(label_keys, k)
			label_values = append(label_values, v)
		}

		for field, value := range fields {
			skip := false
			fieldPromDataType := prometheus.CounterValue

			if msg.MetricDefinitionDetails.ColumnAttrs.PrometheusAllGaugeColumns {
				fieldPromDataType = prometheus.GaugeValue
			} else {
				for _, gaugeColumns := range msg.MetricDefinitionDetails.ColumnAttrs.PrometheusGaugeColumns {
					if gaugeColumns == field {
						fieldPromDataType = prometheus.GaugeValue
						break
					}
				}
			}
			for _, ignoredColumns := range msg.MetricDefinitionDetails.ColumnAttrs.PrometheusIgnoredColumns {
				if ignoredColumns == field {
					skip = true
					break
				}
			}
			if skip {
				continue
			}
			var desc *prometheus.Desc
			if opts.PrometheusNamespace != "" {
				desc = prometheus.NewDesc(fmt.Sprintf("%s_%s_%s", opts.PrometheusNamespace, msg.MetricName, field),
					msg.MetricName, label_keys, nil)
			} else {
				desc = prometheus.NewDesc(fmt.Sprintf("%s_%s", msg.MetricName, field), msg.MetricName, label_keys, nil)
			}
			m := prometheus.MustNewConstMetric(desc, fieldPromDataType, value, label_values...)
			promMetrics = append(promMetrics, prometheus.NewMetricWithTimestamp(epoch_time, m))
		}
	}
	return promMetrics
}

func StartPrometheusExporter(port int64) {
	listenLoops := 0
	promExporter, err := NewExporter()
	if err != nil {
		log.Fatal(err)
	}

	prometheus.MustRegister(promExporter)

	var promServer = &http.Server{Addr: fmt.Sprintf("%s:%d", opts.PrometheusListenAddr, opts.PrometheusPort), Handler: promhttp.Handler()}

	for { // ListenAndServe call should not normally return, but looping just in case
		log.Infof("starting Prometheus exporter on %s:%d ...", opts.PrometheusListenAddr, opts.PrometheusPort)
		err = promServer.ListenAndServe()
		if listenLoops == 0 {
			log.Fatal("Prometheus listener failure:", err)
		} else {
			log.Error("Prometheus listener failure:", err)
		}
		time.Sleep(time.Second * 5)
	}
}
