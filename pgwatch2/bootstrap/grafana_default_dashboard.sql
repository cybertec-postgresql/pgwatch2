insert into dashboard (version, slug, title, org_id, created, updated, updated_by, created_by, gnet_id, data)
values (0, 'documentation', 'Documentation', 1, now(), now(), 1, 1, 0,
'{"annotations":{"list":[]},"editable":true,"gnetId":null,"hideControls":false,"id":1,"links":[],"rows":[{"collapse":false,"height":"250px","panels":[{"content":"# Available measurements (tables with metric info)\n\n\n\n### NB! Metrics that are actually gathered need to be configured for every DB separately (\"monitored_host\" table in the \"pgwatch2\" DB)\n\n\n\n\n* backends - active, total, waiting sessions\n* bgwriter - pg_stat_bgwriter snapshots\n* cpu_load - CPU load info acquiered via a plpython sproc (/pgwatch2/sql/metric_fetching_helpers/)\n* db_stats - pg_stat_database snapshots + DB size info\n* index_stats - pg_stat_user_indexes snapshots\n* kpi - most important high level metrics\n* replication - pg_stat_replication info\n* sproc_stats - pg_stat_user_functions snapshots\n* table_io_stats - pg_statio_user_tables snapshots\n* stat_statements - pg_stat_statements snapshots (requires the extension) \n* table_stats - pg_stat_user_tables snapshots\n* wal - pg_current_xlog_location() values\n\n\n\n# For getting started with Grafana in general start [here](http://docs.grafana.org/guides/getting_started/)\n\n\n\n# For learning InfluxDB query language InfuxQL start [here](https://docs.influxdata.com/influxdb/v1.1/query_language/)\n\n# When stuck then additional support and consultations are available from Cybertec - http://www.cybertec.at/kontakt/","editable":true,"error":false,"id":1,"links":[],"mode":"markdown","span":12,"title":"Documentation","type":"text"}],"repeat":null,"repeatIteration":null,"repeatRowId":null,"showTitle":false,"title":"Row","titleSize":"h6"},{"collapse":false,"height":250,"panels":[{"content":"Brought to you by: \u003ca href=\"http://cybertec.at/en\"\u003e\u003cimg src=\"http://static.cybertec.at/wp-content/themes/cybertec-optimus/assets/img/logo.png\" alt=\"Cybertec – The PostgreSQL Database Company\"\u003e\u003c/a\u003e","editable":true,"error":false,"id":2,"links":[],"mode":"html","span":12,"title":"","transparent":true,"type":"text"}],"repeat":null,"repeatIteration":null,"repeatRowId":null,"showTitle":false,"title":"Dashboard Row","titleSize":"h6"}],"schemaVersion":13,"sharedCrosshair":false,"style":"dark","tags":[],"templating":{"list":[]},"time":{"from":"now-1h","to":"now"},"timepicker":{"refresh_intervals":["5s","10s","30s","1m","5m","15m","30m","1h","2h","1d"],"time_options":["5m","15m","1h","6h","12h","24h","2d","7d","30d"]},"timezone":"browser","title":"Documentation","version":0}'
);


insert into dashboard (version, slug, title, org_id, created, updated, updated_by, created_by, gnet_id, data)
values (0, 'db-overview', 'DB overview', 1, now(), now(), 1, 1, 0,
'
{
  "id": 2,
  "title": "DB overview",
  "tags": [],
  "style": "dark",
  "timezone": "browser",
  "editable": true,
  "sharedCrosshair": false,
  "hideControls": false,
  "time": {
    "from": "now-1h",
    "to": "now"
  },
  "timepicker": {
    "refresh_intervals": [
      "5s",
      "10s",
      "30s",
      "1m",
      "5m",
      "15m",
      "30m",
      "1h",
      "2h",
      "1d"
    ],
    "time_options": [
      "5m",
      "15m",
      "1h",
      "6h",
      "12h",
      "24h",
      "2d",
      "7d",
      "30d"
    ]
  },
  "templating": {
    "list": [
      {
        "allValue": null,
        "current": {
          "text": "test",
          "value": "test"
        },
        "datasource": null,
        "hide": 0,
        "includeAll": false,
        "label": null,
        "multi": false,
        "name": "dbname",
        "options": [],
        "query": "SHOW TAG VALUES WITH KEY = \"dbname\" ",
        "refresh": 1,
        "regex": "",
        "sort": 0,
        "tagValuesQuery": null,
        "tagsQuery": null,
        "type": "query"
      }
    ]
  },
  "annotations": {
    "list": []
  },
  "schemaVersion": 13,
  "version": 1,
  "links": [],
  "gnetId": null,
  "rows": [
    {
      "title": "Row",
      "panels": [
        {
          "aliasColors": {},
          "bars": false,
          "datasource": null,
          "decimals": 1,
          "editable": true,
          "error": false,
          "fill": 1,
          "grid": {},
          "id": 1,
          "legend": {
            "alignAsTable": false,
            "avg": true,
            "current": false,
            "max": false,
            "min": false,
            "show": true,
            "total": false,
            "values": true
          },
          "lines": true,
          "linewidth": 2,
          "links": [],
          "nullPointMode": "connected",
          "percentage": false,
          "pointradius": 5,
          "points": false,
          "renderer": "flot",
          "seriesOverrides": [
            {
              "alias": "WAL ratio (bytes/h)",
              "yaxis": 2
            }
          ],
          "span": 6,
          "stack": false,
          "steppedLine": false,
          "targets": [
            {
              "alias": "WAL ratio (bytes/h)",
              "dsType": "influxdb",
              "groupBy": [
                {
                  "params": [
                    "$interval"
                  ],
                  "type": "time"
                },
                {
                  "params": [
                    "null"
                  ],
                  "type": "fill"
                }
              ],
              "measurement": "wal",
              "policy": "default",
              "query": "SELECT derivative(mean(\"xlog_location_b\"), 1h) FROM \"wal\" WHERE \"dbname\" =~ /^$dbname$/ AND $timeFilter GROUP BY time($interval) fill(null)",
              "rawQuery": true,
              "refId": "A",
              "resultFormat": "time_series",
              "select": [
                [
                  {
                    "params": [
                      "xlog_location_b"
                    ],
                    "type": "field"
                  },
                  {
                    "params": [],
                    "type": "mean"
                  },
                  {
                    "params": [
                      "1h"
                    ],
                    "type": "derivative"
                  }
                ]
              ],
              "tags": [
                {
                  "key": "dbname",
                  "operator": "=~",
                  "value": "/^$dbname$/"
                }
              ]
            },
            {
              "alias": "DB Size",
              "dsType": "influxdb",
              "groupBy": [
                {
                  "params": [
                    "$interval"
                  ],
                  "type": "time"
                },
                {
                  "params": [
                    "null"
                  ],
                  "type": "fill"
                }
              ],
              "measurement": "db_stats",
              "policy": "default",
              "refId": "B",
              "resultFormat": "time_series",
              "select": [
                [
                  {
                    "params": [
                      "size_b"
                    ],
                    "type": "field"
                  },
                  {
                    "params": [],
                    "type": "mean"
                  }
                ]
              ],
              "tags": [
                {
                  "key": "dbname",
                  "operator": "=~",
                  "value": "/^$dbname$/"
                }
              ]
            }
          ],
          "thresholds": [],
          "timeFrom": null,
          "timeShift": null,
          "title": "DB size + WAL write ratio (1h)",
          "tooltip": {
            "msResolution": false,
            "shared": true,
            "sort": 0,
            "value_type": "cumulative"
          },
          "type": "graph",
          "xaxis": {
            "mode": "time",
            "name": null,
            "show": true,
            "values": []
          },
          "yaxes": [
            {
              "format": "bytes",
              "label": null,
              "logBase": 1,
              "max": null,
              "min": null,
              "show": true
            },
            {
              "format": "bytes",
              "label": null,
              "logBase": 1,
              "max": null,
              "min": null,
              "show": true
            }
          ]
        },
        {
          "cacheTimeout": null,
          "colorBackground": false,
          "colorValue": false,
          "colors": [
            "rgba(245, 54, 54, 0.9)",
            "rgba(237, 129, 40, 0.89)",
            "rgba(50, 172, 45, 0.97)"
          ],
          "datasource": null,
          "editable": true,
          "error": false,
          "format": "none",
          "gauge": {
            "maxValue": 100,
            "minValue": 0,
            "show": false,
            "thresholdLabels": false,
            "thresholdMarkers": true
          },
          "id": 4,
          "interval": null,
          "links": [],
          "mappingType": 1,
          "mappingTypes": [
            {
              "name": "value to text",
              "value": 1
            },
            {
              "name": "range to text",
              "value": 2
            }
          ],
          "maxDataPoints": 100,
          "nullPointMode": "connected",
          "nullText": null,
          "postfix": "",
          "postfixFontSize": "50%",
          "prefix": "",
          "prefixFontSize": "50%",
          "rangeMaps": [
            {
              "from": "null",
              "text": "N/A",
              "to": "null"
            }
          ],
          "span": 3,
          "sparkline": {
            "fillColor": "rgba(31, 118, 189, 0.18)",
            "full": true,
            "lineColor": "rgb(31, 120, 193)",
            "show": true
          },
          "targets": [
            {
              "alias": "TPS",
              "dsType": "influxdb",
              "groupBy": [
                {
                  "params": [
                    "$interval"
                  ],
                  "type": "time"
                },
                {
                  "params": [
                    "null"
                  ],
                  "type": "fill"
                }
              ],
              "policy": "default",
              "query": "SELECT non_negative_derivative(mean(\"xact_commit\"), 1s) + non_negative_derivative(mean(\"xact_rollback\"), 1s) FROM \"db_stats\" WHERE \"dbname\" =~ /^$dbname$/ AND  $timeFilter GROUP BY time($interval) fill(null)",
              "rawQuery": true,
              "refId": "A",
              "resultFormat": "time_series",
              "select": [
                [
                  {
                    "params": [
                      "value"
                    ],
                    "type": "field"
                  },
                  {
                    "params": [],
                    "type": "mean"
                  }
                ]
              ],
              "tags": []
            }
          ],
          "thresholds": "",
          "timeFrom": "6h",
          "title": "TPS",
          "type": "singlestat",
          "valueFontSize": "80%",
          "valueMaps": [
            {
              "op": "=",
              "text": "N/A",
              "value": "null"
            }
          ],
          "valueName": "avg"
        },
        {
          "cacheTimeout": null,
          "colorBackground": false,
          "colorValue": false,
          "colors": [
            "rgba(245, 54, 54, 0.9)",
            "rgba(237, 129, 40, 0.89)",
            "rgba(50, 172, 45, 0.97)"
          ],
          "datasource": null,
          "editable": true,
          "error": false,
          "format": "none",
          "gauge": {
            "maxValue": 100,
            "minValue": 0,
            "show": false,
            "thresholdLabels": false,
            "thresholdMarkers": true
          },
          "id": 5,
          "interval": null,
          "links": [],
          "mappingType": 1,
          "mappingTypes": [
            {
              "name": "value to text",
              "value": 1
            },
            {
              "name": "range to text",
              "value": 2
            }
          ],
          "maxDataPoints": 100,
          "nullPointMode": "connected",
          "nullText": null,
          "postfix": " ms",
          "postfixFontSize": "50%",
          "prefix": "",
          "prefixFontSize": "50%",
          "rangeMaps": [
            {
              "from": "null",
              "text": "N/A",
              "to": "null"
            }
          ],
          "span": 3,
          "sparkline": {
            "fillColor": "rgba(31, 118, 189, 0.18)",
            "full": true,
            "lineColor": "rgb(31, 120, 193)",
            "show": true
          },
          "targets": [
            {
              "alias": "avg_query_runtime_per_db",
              "dsType": "influxdb",
              "groupBy": [
                {
                  "params": [
                    "$interval"
                  ],
                  "type": "time"
                },
                {
                  "params": [
                    "null"
                  ],
                  "type": "fill"
                }
              ],
              "policy": "default",
              "query": "SELECT non_negative_derivative(last(\"total_time\"), 1h) / non_negative_derivative(last(\"calls\"), 1h) FROM \"stat_statements\" WHERE \"dbname\" =~ /^$dbname$/ AND $timeFilter GROUP BY time($interval) fill(none)",
              "rawQuery": true,
              "refId": "A",
              "resultFormat": "time_series",
              "select": [
                [
                  {
                    "params": [
                      "value"
                    ],
                    "type": "field"
                  },
                  {
                    "params": [],
                    "type": "mean"
                  }
                ]
              ],
              "tags": []
            }
          ],
          "thresholds": "",
          "timeFrom": "6h",
          "timeShift": null,
          "title": "Avg. query runtime",
          "type": "singlestat",
          "valueFontSize": "80%",
          "valueMaps": [
            {
              "op": "=",
              "text": "N/A",
              "value": "null"
            }
          ],
          "valueName": "avg"
        }
      ],
      "showTitle": false,
      "titleSize": "h6",
      "height": "250px",
      "repeat": null,
      "repeatRowId": null,
      "repeatIteration": null,
      "collapse": false
    },
    {
      "title": "New row",
      "panels": [
        {
          "aliasColors": {},
          "bars": false,
          "datasource": null,
          "editable": true,
          "error": false,
          "fill": 1,
          "grid": {},
          "id": 3,
          "legend": {
            "alignAsTable": false,
            "avg": true,
            "current": false,
            "max": false,
            "min": false,
            "show": true,
            "total": false,
            "values": true
          },
          "lines": true,
          "linewidth": 2,
          "links": [],
          "nullPointMode": "connected",
          "percentage": false,
          "pointradius": 5,
          "points": false,
          "renderer": "flot",
          "seriesOverrides": [
            {
              "alias": "db_stats.mean",
              "yaxis": 2
            },
            {
              "alias": "DB size",
              "yaxis": 2
            },
            {
              "alias": "blk_read_time",
              "yaxis": 2
            },
            {
              "alias": "blk_write_time",
              "yaxis": 2
            }
          ],
          "span": 6,
          "stack": false,
          "steppedLine": false,
          "targets": [
            {
              "alias": "DELETE",
              "dsType": "influxdb",
              "groupBy": [
                {
                  "params": [
                    "$interval"
                  ],
                  "type": "time"
                },
                {
                  "params": [
                    "null"
                  ],
                  "type": "fill"
                }
              ],
              "measurement": "db_stats",
              "policy": "default",
              "query": "SELECT non_negative_derivative(mean(\"tup_deleted\"), 1h) FROM \"db_stats\" WHERE \"dbname\" =~ /^$dbname$/ AND $timeFilter GROUP BY time($interval) fill(null)",
              "rawQuery": true,
              "refId": "A",
              "resultFormat": "time_series",
              "select": [
                [
                  {
                    "params": [
                      "tup_deleted"
                    ],
                    "type": "field"
                  },
                  {
                    "params": [],
                    "type": "mean"
                  }
                ]
              ],
              "tags": [
                {
                  "key": "dbname",
                  "operator": "=~",
                  "value": "/^$dbname$/"
                }
              ]
            },
            {
              "alias": "UPDATE",
              "dsType": "influxdb",
              "groupBy": [
                {
                  "params": [
                    "$interval"
                  ],
                  "type": "time"
                },
                {
                  "params": [
                    "null"
                  ],
                  "type": "fill"
                }
              ],
              "policy": "default",
              "query": "SELECT non_negative_derivative(mean(\"tup_updated\"), 1h) FROM \"db_stats\" WHERE \"dbname\" =~ /^$dbname$/ AND $timeFilter GROUP BY time($interval) fill(null)",
              "rawQuery": true,
              "refId": "B",
              "resultFormat": "time_series",
              "select": [
                [
                  {
                    "params": [
                      "value"
                    ],
                    "type": "field"
                  },
                  {
                    "params": [],
                    "type": "mean"
                  }
                ]
              ],
              "tags": []
            },
            {
              "alias": "INSERT",
              "dsType": "influxdb",
              "groupBy": [
                {
                  "params": [
                    "$interval"
                  ],
                  "type": "time"
                },
                {
                  "params": [
                    "null"
                  ],
                  "type": "fill"
                }
              ],
              "policy": "default",
              "query": "SELECT non_negative_derivative(mean(\"tup_inserted\"), 1h) FROM \"db_stats\" WHERE \"dbname\" =~ /^$dbname$/ AND $timeFilter GROUP BY time($interval) fill(null)",
              "rawQuery": true,
              "refId": "C",
              "resultFormat": "time_series",
              "select": [
                [
                  {
                    "params": [
                      "value"
                    ],
                    "type": "field"
                  },
                  {
                    "params": [],
                    "type": "mean"
                  }
                ]
              ],
              "tags": []
            },
            {
              "alias": "blk_read_time",
              "dsType": "influxdb",
              "groupBy": [
                {
                  "params": [
                    "$interval"
                  ],
                  "type": "time"
                },
                {
                  "params": [
                    "null"
                  ],
                  "type": "fill"
                }
              ],
              "policy": "default",
              "query": "SELECT non_negative_derivative(mean(\"blk_read_time\"), 1h) FROM \"db_stats\" WHERE \"dbname\" =~ /^$dbname$/ AND $timeFilter GROUP BY time($interval) fill(null)",
              "rawQuery": true,
              "refId": "E",
              "resultFormat": "time_series",
              "select": [
                [
                  {
                    "params": [
                      "value"
                    ],
                    "type": "field"
                  },
                  {
                    "params": [],
                    "type": "mean"
                  }
                ]
              ],
              "tags": []
            },
            {
              "alias": "blk_write_time",
              "dsType": "influxdb",
              "groupBy": [
                {
                  "params": [
                    "$interval"
                  ],
                  "type": "time"
                },
                {
                  "params": [
                    "null"
                  ],
                  "type": "fill"
                }
              ],
              "policy": "default",
              "query": "SELECT non_negative_derivative(mean(\"blk_write_time\"), 1h) FROM \"db_stats\" WHERE \"dbname\" =~ /^$dbname$/ AND $timeFilter GROUP BY time($interval) fill(null)",
              "rawQuery": true,
              "refId": "F",
              "resultFormat": "time_series",
              "select": [
                [
                  {
                    "params": [
                      "value"
                    ],
                    "type": "field"
                  },
                  {
                    "params": [],
                    "type": "mean"
                  }
                ]
              ],
              "tags": []
            }
          ],
          "thresholds": [],
          "timeFrom": null,
          "timeShift": null,
          "title": "Tuple IUD statistics + IO times (1h ratios)",
          "tooltip": {
            "msResolution": false,
            "shared": true,
            "sort": 0,
            "value_type": "cumulative"
          },
          "type": "graph",
          "xaxis": {
            "mode": "time",
            "name": null,
            "show": true,
            "values": []
          },
          "yaxes": [
            {
              "format": "short",
              "label": null,
              "logBase": 10,
              "max": null,
              "min": null,
              "show": true
            },
            {
              "format": "ms",
              "label": null,
              "logBase": 1,
              "max": null,
              "min": null,
              "show": true
            }
          ]
        },
        {
          "aliasColors": {},
          "bars": false,
          "datasource": null,
          "decimals": 1,
          "editable": true,
          "error": false,
          "fill": 1,
          "grid": {},
          "id": 2,
          "legend": {
            "alignAsTable": false,
            "avg": true,
            "current": false,
            "max": false,
            "min": false,
            "show": true,
            "total": false,
            "values": true
          },
          "lines": true,
          "linewidth": 2,
          "links": [],
          "nullPointMode": "connected",
          "percentage": false,
          "pointradius": 5,
          "points": false,
          "renderer": "flot",
          "seriesOverrides": [],
          "span": 6,
          "stack": false,
          "steppedLine": false,
          "targets": [
            {
              "alias": "Shared buffers hit ratio",
              "dsType": "influxdb",
              "groupBy": [
                {
                  "params": [
                    "$interval"
                  ],
                  "type": "time"
                },
                {
                  "params": [
                    "null"
                  ],
                  "type": "fill"
                }
              ],
              "hide": false,
              "measurement": "db_stats",
              "policy": "default",
              "query": "SELECT ( non_negative_derivative(mean(\"blks_hit\")) / (non_negative_derivative(mean(\"blks_hit\")) + non_negative_derivative(mean(\"blks_read\")))) * 100 FROM \"db_stats\" WHERE \"dbname\" =~ /^$dbname$/ AND  $timeFilter GROUP BY time($interval) fill(null)",
              "rawQuery": true,
              "refId": "A",
              "resultFormat": "time_series",
              "select": [
                [
                  {
                    "params": [
                      "blks_hit"
                    ],
                    "type": "field"
                  },
                  {
                    "params": [],
                    "type": "mean"
                  }
                ]
              ],
              "tags": []
            },
            {
              "alias": "TX rollback ratio",
              "dsType": "influxdb",
              "groupBy": [
                {
                  "params": [
                    "$interval"
                  ],
                  "type": "time"
                },
                {
                  "params": [
                    "null"
                  ],
                  "type": "fill"
                }
              ],
              "hide": false,
              "policy": "default",
              "query": "SELECT (non_negative_derivative(mean(\"xact_rollback\")) / (non_negative_derivative(mean(\"xact_commit\")) + non_negative_derivative(mean(\"xact_rollback\"))) * 100) FROM \"db_stats\" WHERE \"dbname\" =~ /^$dbname$/ AND  $timeFilter GROUP BY time($interval) fill(null)",
              "rawQuery": true,
              "refId": "B",
              "resultFormat": "time_series",
              "select": [
                [
                  {
                    "params": [
                      "value"
                    ],
                    "type": "field"
                  },
                  {
                    "params": [],
                    "type": "mean"
                  }
                ]
              ],
              "tags": []
            }
          ],
          "thresholds": [],
          "timeFrom": null,
          "timeShift": null,
          "title": "Buffer hit ratio + Rollback ratio",
          "tooltip": {
            "msResolution": false,
            "shared": true,
            "sort": 0,
            "value_type": "cumulative"
          },
          "type": "graph",
          "xaxis": {
            "mode": "time",
            "name": null,
            "show": true,
            "values": []
          },
          "yaxes": [
            {
              "format": "percent",
              "label": null,
              "logBase": 1,
              "max": null,
              "min": null,
              "show": true
            },
            {
              "format": "short",
              "label": null,
              "logBase": 1,
              "max": null,
              "min": null,
              "show": true
            }
          ]
        }
      ],
      "showTitle": false,
      "titleSize": "h6",
      "height": "250px",
      "repeat": null,
      "repeatRowId": null,
      "repeatIteration": null,
      "collapse": false
    },
    {
      "title": "New row",
      "panels": [
        {
          "aliasColors": {},
          "bars": false,
          "datasource": null,
          "editable": true,
          "error": false,
          "fill": 1,
          "grid": {},
          "id": 6,
          "legend": {
            "avg": false,
            "current": false,
            "max": false,
            "min": false,
            "show": true,
            "total": false,
            "values": false
          },
          "lines": true,
          "linewidth": 2,
          "links": [],
          "nullPointMode": "connected",
          "percentage": false,
          "pointradius": 5,
          "points": false,
          "renderer": "flot",
          "seriesOverrides": [
            {
              "alias": "Deadlocks (1h rate)",
              "yaxis": 1
            },
            {
              "alias": "Temp bytes written",
              "yaxis": 2
            }
          ],
          "span": 12,
          "stack": false,
          "steppedLine": false,
          "targets": [
            {
              "alias": "Deadlocks (1h rate)",
              "dsType": "influxdb",
              "groupBy": [
                {
                  "params": [
                    "$interval"
                  ],
                  "type": "time"
                },
                {
                  "params": [
                    "null"
                  ],
                  "type": "fill"
                }
              ],
              "policy": "default",
              "query": "SELECT non_negative_derivative(mean(\"deadlocks\")) FROM \"db_stats\" WHERE \"dbname\" =~ /^$dbname$/ AND  $timeFilter GROUP BY time($interval) fill(null)",
              "rawQuery": true,
              "refId": "A",
              "resultFormat": "time_series",
              "select": [
                [
                  {
                    "params": [
                      "value"
                    ],
                    "type": "field"
                  },
                  {
                    "params": [],
                    "type": "mean"
                  }
                ]
              ],
              "tags": []
            },
            {
              "alias": "#Backends",
              "dsType": "influxdb",
              "groupBy": [
                {
                  "params": [
                    "$interval"
                  ],
                  "type": "time"
                },
                {
                  "params": [
                    "null"
                  ],
                  "type": "fill"
                }
              ],
              "measurement": "db_stats",
              "policy": "default",
              "refId": "B",
              "resultFormat": "time_series",
              "select": [
                [
                  {
                    "params": [
                      "numbackends"
                    ],
                    "type": "field"
                  },
                  {
                    "params": [],
                    "type": "mean"
                  }
                ]
              ],
              "tags": []
            },
            {
              "alias": "Temp bytes written",
              "dsType": "influxdb",
              "groupBy": [
                {
                  "params": [
                    "$interval"
                  ],
                  "type": "time"
                },
                {
                  "params": [
                    "null"
                  ],
                  "type": "fill"
                }
              ],
              "policy": "default",
              "query": "SELECT non_negative_derivative(mean(\"temp_bytes\")) FROM \"db_stats\" WHERE \"dbname\" =~ /^$dbname$/ AND  $timeFilter GROUP BY time($interval) fill(null)",
              "rawQuery": true,
              "refId": "C",
              "resultFormat": "time_series",
              "select": [
                [
                  {
                    "params": [
                      "value"
                    ],
                    "type": "field"
                  },
                  {
                    "params": [],
                    "type": "mean"
                  }
                ]
              ],
              "tags": []
            }
          ],
          "thresholds": [],
          "timeFrom": null,
          "timeShift": null,
          "title": "Backends + Deadlocks + Temp bytes",
          "tooltip": {
            "msResolution": false,
            "shared": true,
            "sort": 0,
            "value_type": "cumulative"
          },
          "type": "graph",
          "xaxis": {
            "mode": "time",
            "name": null,
            "show": true,
            "values": []
          },
          "yaxes": [
            {
              "format": "short",
              "label": null,
              "logBase": 1,
              "max": null,
              "min": null,
              "show": true
            },
            {
              "format": "Bps",
              "label": null,
              "logBase": 1,
              "max": null,
              "min": null,
              "show": true
            }
          ]
        }
      ],
      "showTitle": false,
      "titleSize": "h6",
      "height": "250px",
      "repeat": null,
      "repeatRowId": null,
      "repeatIteration": null,
      "collapse": false
    },
    {
      "title": "Dashboard Row",
      "panels": [
        {
          "content": "Brought to you by: <a href=\"http://cybertec.at/en\"><img src=\"http://static.cybertec.at/wp-content/themes/cybertec-optimus/assets/img/logo.png\" alt=\"Cybertec – The PostgreSQL Database Company\"></a>",
          "editable": true,
          "error": false,
          "id": 7,
          "links": [],
          "mode": "html",
          "span": 12,
          "title": "",
          "transparent": true,
          "type": "text"
        }
      ],
      "showTitle": false,
      "titleSize": "h6",
      "height": 250,
      "repeat": null,
      "repeatRowId": null,
      "repeatIteration": null,
      "collapse": false
    }
  ]
}
'
);

insert into dashboard (version, slug, title, org_id, created, updated, updated_by, created_by, gnet_id, data)
values (1, 'table-details', 'Table details', 1, now(), now(), 1, 1, 0,
'{"annotations":{"list":[]},"editable":true,"gnetId":null,"hideControls":false,"id":3,"links":[],"rows":[{"collapse":false,"height":"250px","panels":[{"aliasColors":{},"bars":false,"datasource":null,"editable":true,"error":false,"fill":1,"id":1,"legend":{"avg":false,"current":false,"max":false,"min":false,"show":true,"total":false,"values":false},"lines":true,"linewidth":1,"links":[],"nullPointMode":"connected","percentage":false,"pointradius":5,"points":false,"renderer":"flot","seriesOverrides":[{"alias":"table_stats.non_negative_derivative","yaxis":2}],"span":12,"stack":false,"steppedLine":false,"targets":[{"alias":"total_relation_size","dsType":"influxdb","groupBy":[{"params":["$interval"],"type":"time"},{"params":["null"],"type":"fill"}],"measurement":"table_stats","policy":"default","query":"SELECT mean(\"total_relation_size_b\") FROM \"table_stats\" WHERE \"dbname\" =~ /^$dbname$/ AND \"table_name\" =~ /^$table_name$/ AND $timeFilter GROUP BY time($interval) fill(null)","rawQuery":false,"refId":"A","resultFormat":"time_series","select":[[{"params":["total_relation_size_b"],"type":"field"},{"params":[],"type":"mean"}]],"tags":[{"key":"dbname","operator":"=~","value":"/^$dbname$/"}]},{"alias":"table_size","dsType":"influxdb","groupBy":[{"params":["$interval"],"type":"time"},{"params":["null"],"type":"fill"}],"measurement":"table_stats","policy":"default","query":"SELECT mean(\"total_relation_size_b\") FROM \"table_stats\" WHERE \"dbname\" =~ /^$dbname$/ AND \"table_name\" =~ /^$table_name$/ AND $timeFilter GROUP BY time($interval) fill(null)","rawQuery":false,"refId":"B","resultFormat":"time_series","select":[[{"params":["table_size_b"],"type":"field"},{"params":[],"type":"mean"}]],"tags":[{"key":"dbname","operator":"=~","value":"/^$dbname$/"}]},{"alias":"index_size","dsType":"influxdb","groupBy":[{"params":["$interval"],"type":"time"},{"params":["null"],"type":"fill"}],"measurement":"index_stats","policy":"default","query":"SELECT mean(\"total_relation_size_b\") FROM \"table_stats\" WHERE \"dbname\" =~ /^$dbname$/ AND \"table_name\" =~ /^$table_name$/ AND $timeFilter GROUP BY time($interval) fill(null)","rawQuery":false,"refId":"C","resultFormat":"time_series","select":[[{"params":["index_size_b"],"type":"field"},{"params":[],"type":"mean"}]],"tags":[{"key":"dbname","operator":"=~","value":"/^$dbname$/"}]}],"thresholds":[],"timeFrom":null,"timeShift":null,"title":"Size","tooltip":{"msResolution":false,"shared":true,"sort":0,"value_type":"individual"},"type":"graph","xaxis":{"mode":"time","name":null,"show":true,"values":[]},"yaxes":[{"format":"bytes","label":null,"logBase":1,"max":null,"min":null,"show":true},{"format":"short","label":null,"logBase":1,"max":null,"min":null,"show":true}]}],"repeat":null,"repeatIteration":null,"repeatRowId":null,"showTitle":false,"title":"Dashboard Row","titleSize":"h6"},{"collapse":false,"height":250,"panels":[{"aliasColors":{},"bars":false,"datasource":null,"editable":true,"error":false,"fill":1,"id":2,"legend":{"avg":false,"current":false,"max":false,"min":false,"show":true,"total":false,"values":false},"lines":true,"linewidth":1,"links":[],"nullPointMode":"connected","percentage":false,"pointradius":5,"points":false,"renderer":"flot","seriesOverrides":[],"span":12,"stack":false,"steppedLine":false,"targets":[{"alias":"seq_scans","dsType":"influxdb","groupBy":[{"params":["$interval"],"type":"time"},{"params":["null"],"type":"fill"}],"measurement":"table_stats","policy":"default","refId":"A","resultFormat":"time_series","select":[[{"params":["seq_scan"],"type":"field"},{"params":[],"type":"mean"},{"params":["1m"],"type":"non_negative_derivative"}]],"tags":[{"key":"dbname","operator":"=~","value":"/^$dbname$/"}]},{"alias":"idx_scans","dsType":"influxdb","groupBy":[{"params":["$interval"],"type":"time"},{"params":["null"],"type":"fill"}],"measurement":"table_stats","policy":"default","query":"SELECT non_negative_derivative(mean(\"idx_scan\"), 1m) FROM \"table_stats\" WHERE \"dbname\" =~ /^$dbname$/ AND $timeFilter GROUP BY time($interval) fill(null)","rawQuery":false,"refId":"B","resultFormat":"time_series","select":[[{"params":["idx_scan"],"type":"field"},{"params":[],"type":"mean"},{"params":["1m"],"type":"non_negative_derivative"}]],"tags":[{"key":"dbname","operator":"=~","value":"/^$dbname$/"}]}],"thresholds":[],"timeFrom":null,"timeShift":null,"title":"Scans (1/min)","tooltip":{"msResolution":false,"shared":true,"sort":0,"value_type":"individual"},"type":"graph","xaxis":{"mode":"time","name":null,"show":true,"values":[]},"yaxes":[{"format":"short","label":null,"logBase":10,"max":null,"min":null,"show":true},{"format":"short","label":null,"logBase":1,"max":null,"min":null,"show":true}]}],"repeat":null,"repeatIteration":null,"repeatRowId":null,"showTitle":false,"title":"Dashboard Row","titleSize":"h6"},{"collapse":false,"height":250,"panels":[{"aliasColors":{},"bars":false,"datasource":null,"editable":true,"error":false,"fill":1,"id":3,"legend":{"avg":false,"current":false,"max":false,"min":false,"show":true,"total":false,"values":false},"lines":true,"linewidth":1,"links":[],"nullPointMode":"connected","percentage":false,"pointradius":5,"points":false,"renderer":"flot","seriesOverrides":[],"span":12,"stack":false,"steppedLine":false,"targets":[{"alias":"INS","dsType":"influxdb","groupBy":[{"params":["$interval"],"type":"time"},{"params":["null"],"type":"fill"}],"measurement":"table_stats","policy":"default","refId":"A","resultFormat":"time_series","select":[[{"params":["n_tup_ins"],"type":"field"},{"params":[],"type":"mean"},{"params":["1m"],"type":"non_negative_derivative"}]],"tags":[{"key":"dbname","operator":"=~","value":"/^$dbname$/"}]},{"alias":"UPD","dsType":"influxdb","groupBy":[{"params":["$interval"],"type":"time"},{"params":["null"],"type":"fill"}],"measurement":"table_stats","policy":"default","refId":"B","resultFormat":"time_series","select":[[{"params":["n_tup_upd"],"type":"field"},{"params":[],"type":"mean"},{"params":["1m"],"type":"non_negative_derivative"}]],"tags":[{"key":"dbname","operator":"=~","value":"/^$dbname$/"}]},{"alias":"DEL","dsType":"influxdb","groupBy":[{"params":["$interval"],"type":"time"},{"params":["null"],"type":"fill"}],"measurement":"table_stats","policy":"default","refId":"C","resultFormat":"time_series","select":[[{"params":["n_tup_del"],"type":"field"},{"params":[],"type":"mean"},{"params":["1m"],"type":"non_negative_derivative"}]],"tags":[{"key":"dbname","operator":"=~","value":"/^$dbname$/"}]}],"thresholds":[],"timeFrom":null,"timeShift":null,"title":"IUD (1/min)","tooltip":{"msResolution":false,"shared":true,"sort":0,"value_type":"individual"},"type":"graph","xaxis":{"mode":"time","name":null,"show":true,"values":[]},"yaxes":[{"format":"short","label":null,"logBase":10,"max":null,"min":null,"show":true},{"format":"short","label":null,"logBase":1,"max":null,"min":null,"show":true}]}],"repeat":null,"repeatIteration":null,"repeatRowId":null,"showTitle":false,"title":"Dashboard Row","titleSize":"h6"},{"collapse":false,"height":250,"panels":[{"aliasColors":{},"bars":false,"datasource":null,"editable":true,"error":false,"fill":1,"id":4,"legend":{"alignAsTable":false,"avg":true,"current":true,"hideEmpty":false,"hideZero":false,"max":false,"min":false,"show":true,"total":false,"values":true},"lines":true,"linewidth":1,"links":[],"nullPointMode":"null","percentage":false,"pointradius":5,"points":false,"renderer":"flot","seriesOverrides":[],"span":12,"stack":false,"steppedLine":false,"targets":[{"alias":"Heap","dsType":"influxdb","groupBy":[{"params":["$interval"],"type":"time"},{"params":["null"],"type":"fill"}],"measurement":"table_io_stats","policy":"default","query":"SELECT non_negative_derivative(mean(\"heap_blks_hit\"), 10s) /  (non_negative_derivative(mean(\"heap_blks_hit\"), 10s) + non_negative_derivative(mean(\"heap_blks_read\"), 10s)) * 100 FROM \"table_io_stats\" WHERE \"dbname\" =~ /^$dbname$/ AND $timeFilter GROUP BY time($interval) fill(null)","rawQuery":true,"refId":"A","resultFormat":"time_series","select":[[{"params":["heap_blks_hit"],"type":"field"},{"params":[],"type":"mean"},{"params":["10s"],"type":"non_negative_derivative"}]],"tags":[{"key":"dbname","operator":"=~","value":"/^$dbname$/"}]},{"alias":"Indexes","dsType":"influxdb","groupBy":[{"params":["$interval"],"type":"time"},{"params":["null"],"type":"fill"}],"measurement":"table_io_stats","policy":"default","query":"SELECT non_negative_derivative(mean(\"idx_blks_hit\"), 10s) /  (non_negative_derivative(mean(\"idx_blks_hit\"), 10s) + non_negative_derivative(mean(\"idx_blks_read\"), 10s)) * 100 FROM \"table_io_stats\" WHERE \"dbname\" =~ /^$dbname$/ AND $timeFilter GROUP BY time($interval) fill(null)","rawQuery":true,"refId":"B","resultFormat":"time_series","select":[[{"params":["heap_blks_hit"],"type":"field"},{"params":[],"type":"mean"},{"params":["10s"],"type":"non_negative_derivative"}]],"tags":[{"key":"dbname","operator":"=~","value":"/^$dbname$/"}]}],"thresholds":[],"timeFrom":null,"timeShift":null,"title":"Cache rates","tooltip":{"msResolution":false,"shared":true,"sort":0,"value_type":"individual"},"type":"graph","xaxis":{"mode":"time","name":null,"show":true,"values":[]},"yaxes":[{"format":"short","label":null,"logBase":1,"max":null,"min":null,"show":true},{"format":"short","label":null,"logBase":1,"max":null,"min":null,"show":true}]}],"repeat":null,"repeatIteration":null,"repeatRowId":null,"showTitle":false,"title":"Dashboard Row","titleSize":"h6"},{"collapse":false,"height":250,"panels":[{"content":"Brought to you by: \u003ca href=\"http://cybertec.at/en\"\u003e\u003cimg src=\"http://static.cybertec.at/wp-content/themes/cybertec-optimus/assets/img/logo.png\" alt=\"Cybertec – The PostgreSQL Database Company\"\u003e\u003c/a\u003e","editable":true,"error":false,"id":5,"links":[],"mode":"html","span":12,"title":"","transparent":true,"type":"text"}],"repeat":null,"repeatIteration":null,"repeatRowId":null,"showTitle":false,"title":"Dashboard Row","titleSize":"h6"}],"schemaVersion":13,"sharedCrosshair":false,"style":"dark","tags":[],"templating":{"list":[{"allValue":null,"current":{"isNone":true,"text":"None","value":""},"datasource":"Influx","hide":0,"includeAll":false,"label":null,"multi":false,"name":"dbname","options":[],"query":"SHOW TAG VALUES FROM \"table_stats\" WITH KEY = \"dbname\"","refresh":1,"regex":"","sort":0,"tagValuesQuery":null,"tagsQuery":null,"type":"query"},{"datasource":"Influx","filters":[],"hide":0,"label":"User filters","name":"custom_filter","type":"adhoc"}]},"time":{"from":"now-1h","to":"now"},"timepicker":{"refresh_intervals":["5s","10s","30s","1m","5m","15m","30m","1h","2h","1d"],"time_options":["5m","15m","1h","6h","12h","24h","2d","7d","30d"]},"timezone":"browser","title":"Table details","version":0}'
);


insert into dashboard (version, slug, title, org_id, created, updated, updated_by, created_by, gnet_id, data)
values (0, 'statement-details', 'Statement details', 1, now(), now(), 1, 1, 0,
'{
  "id": 4,
  "title": "Statement details",
  "tags": [],
  "style": "dark",
  "timezone": "browser",
  "editable": true,
  "sharedCrosshair": false,
  "hideControls": false,
  "time": {
    "from": "now-1h",
    "to": "now"
  },
  "timepicker": {
    "refresh_intervals": [
      "5s",
      "10s",
      "30s",
      "1m",
      "5m",
      "15m",
      "30m",
      "1h",
      "2h",
      "1d"
    ],
    "time_options": [
      "5m",
      "15m",
      "1h",
      "6h",
      "12h",
      "24h",
      "2d",
      "7d",
      "30d"
    ]
  },
  "templating": {
    "list": [
      {
        "type": "query",
        "label": null,
        "query": "SHOW TAG VALUES WITH KEY = \"dbname\"",
        "regex": "",
        "sort": 1,
        "datasource": "Influx",
        "refresh": 1,
        "hide": 0,
        "name": "dbname",
        "multi": false,
        "includeAll": false,
        "allValue": null,
        "options": [],
        "current": {
          "text": "test",
          "value": "test"
        },
        "tagsQuery": null,
        "tagValuesQuery": null
      }
    ]
  },
  "annotations": {
    "list": []
  },
  "schemaVersion": 13,
  "version": 0,
  "links": [],
  "gnetId": null,
  "rows": [
    {
      "title": "Dashboard Row",
      "panels": [
        {
          "id": 5,
          "title": "Query runtime per DB",
          "error": false,
          "span": 12,
          "editable": true,
          "type": "graph",
          "targets": [
            {
              "policy": "default",
              "dsType": "influxdb",
              "resultFormat": "time_series",
              "tags": [],
              "groupBy": [
                {
                  "type": "time",
                  "params": [
                    "$interval"
                  ]
                },
                {
                  "type": "fill",
                  "params": [
                    "null"
                  ]
                }
              ],
              "select": [
                [
                  {
                    "type": "field",
                    "params": [
                      "calls"
                    ]
                  },
                  {
                    "type": "mean",
                    "params": []
                  }
                ]
              ],
              "refId": "A",
              "measurement": "stat_statements",
              "query": "SELECT non_negative_derivative(last(\"total_time\"), 1h) / non_negative_derivative(last(\"calls\"), 1h) FROM \"stat_statements\" WHERE \"dbname\" =~ /^$dbname$/ AND $timeFilter GROUP BY time($interval) fill(none)",
              "rawQuery": true,
              "alias": "avg_query_runtime"
            }
          ],
          "datasource": null,
          "renderer": "flot",
          "yaxes": [
            {
              "label": null,
              "show": true,
              "logBase": 1,
              "min": null,
              "max": null,
              "format": "ms"
            },
            {
              "label": null,
              "show": true,
              "logBase": 1,
              "min": null,
              "max": null,
              "format": "short"
            }
          ],
          "xaxis": {
            "show": true,
            "mode": "time",
            "name": null,
            "values": []
          },
          "lines": true,
          "fill": 1,
          "linewidth": 1,
          "points": false,
          "pointradius": 5,
          "bars": false,
          "stack": false,
          "percentage": false,
          "legend": {
            "show": true,
            "values": false,
            "min": false,
            "max": false,
            "current": false,
            "total": false,
            "avg": false,
            "hideEmpty": true,
            "hideZero": true
          },
          "nullPointMode": "connected",
          "steppedLine": false,
          "tooltip": {
            "value_type": "individual",
            "shared": true,
            "sort": 0,
            "msResolution": false
          },
          "timeFrom": null,
          "timeShift": null,
          "aliasColors": {},
          "seriesOverrides": [],
          "thresholds": [],
          "links": []
        }
      ],
      "showTitle": false,
      "titleSize": "h6",
      "height": 250,
      "repeat": null,
      "repeatRowId": null,
      "repeatIteration": null,
      "collapse": false
    },
    {
      "title": "Row",
      "panels": [
        {
          "aliasColors": {},
          "bars": false,
          "datasource": "Influx",
          "editable": true,
          "error": false,
          "fill": 1,
          "grid": {},
          "id": 1,
          "legend": {
            "avg": false,
            "current": false,
            "hideEmpty": true,
            "hideZero": true,
            "max": false,
            "min": false,
            "show": true,
            "total": false,
            "values": false
          },
          "lines": true,
          "linewidth": 2,
          "links": [],
          "nullPointMode": "connected",
          "percentage": false,
          "pointradius": 5,
          "points": false,
          "renderer": "flot",
          "seriesOverrides": [],
          "span": 12,
          "stack": false,
          "steppedLine": false,
          "targets": [
            {
              "alias": "$tag_queryid",
              "dsType": "influxdb",
              "groupBy": [
                {
                  "params": [
                    "$interval"
                  ],
                  "type": "time"
                },
                {
                  "params": [
                    "queryid"
                  ],
                  "type": "tag"
                },
                {
                  "params": [
                    "none"
                  ],
                  "type": "fill"
                }
              ],
              "measurement": "stat_statements",
              "policy": "default",
              "query": "SELECT non_negative_derivative(mean(\"total_time\"), 1h) / non_negative_derivative(mean(\"calls\"), 1h) FROM \"stat_statements\" WHERE \"dbname\" =~ /^$dbname$/ AND $timeFilter GROUP BY time($interval), \"queryid\" fill(none)",
              "rawQuery": true,
              "refId": "A",
              "resultFormat": "time_series",
              "select": [
                [
                  {
                    "params": [
                      "total_time"
                    ],
                    "type": "field"
                  },
                  {
                    "params": [],
                    "type": "mean"
                  },
                  {
                    "params": [
                      "1h"
                    ],
                    "type": "non_negative_derivative"
                  }
                ]
              ],
              "tags": []
            }
          ],
          "thresholds": [],
          "timeFrom": null,
          "timeShift": null,
          "title": "Query runtime per query",
          "tooltip": {
            "msResolution": true,
            "shared": false,
            "sort": 2,
            "value_type": "cumulative"
          },
          "type": "graph",
          "xaxis": {
            "mode": "time",
            "name": null,
            "show": true,
            "values": []
          },
          "yaxes": [
            {
              "format": "ms",
              "label": "",
              "logBase": 1,
              "max": null,
              "min": null,
              "show": true
            },
            {
              "format": "short",
              "label": null,
              "logBase": 1,
              "max": null,
              "min": null,
              "show": true
            }
          ]
        },
        {
          "aliasColors": {},
          "bars": false,
          "datasource": "Influx",
          "editable": true,
          "error": false,
          "fill": 1,
          "grid": {},
          "id": 2,
          "legend": {
            "avg": false,
            "current": false,
            "hideEmpty": true,
            "hideZero": true,
            "max": false,
            "min": false,
            "show": true,
            "total": false,
            "values": false
          },
          "lines": true,
          "linewidth": 2,
          "links": [],
          "nullPointMode": "connected",
          "percentage": false,
          "pointradius": 5,
          "points": false,
          "renderer": "flot",
          "seriesOverrides": [],
          "span": 12,
          "stack": false,
          "steppedLine": false,
          "targets": [
            {
              "alias": "$tag_queryid",
              "dsType": "influxdb",
              "groupBy": [
                {
                  "params": [
                    "$interval"
                  ],
                  "type": "time"
                },
                {
                  "params": [
                    "queryid"
                  ],
                  "type": "tag"
                },
                {
                  "params": [
                    "none"
                  ],
                  "type": "fill"
                }
              ],
              "measurement": "stat_statements",
              "policy": "default",
              "query": "SELECT non_negative_derivative(mean(\"total_time\"), 1h) FROM \"stat_statements\" WHERE \"dbname\" =~ /^$dbname$/ AND $timeFilter GROUP BY time($interval), \"queryid\" fill(none)",
              "rawQuery": true,
              "refId": "A",
              "resultFormat": "time_series",
              "select": [
                [
                  {
                    "params": [
                      "total_time"
                    ],
                    "type": "field"
                  },
                  {
                    "params": [],
                    "type": "mean"
                  },
                  {
                    "params": [
                      "1h"
                    ],
                    "type": "non_negative_derivative"
                  }
                ]
              ],
              "tags": []
            }
          ],
          "thresholds": [],
          "timeFrom": null,
          "timeShift": null,
          "title": "Cumulative per query runtime (1h ratio)",
          "tooltip": {
            "msResolution": true,
            "shared": false,
            "sort": 2,
            "value_type": "cumulative"
          },
          "type": "graph",
          "xaxis": {
            "mode": "time",
            "name": null,
            "show": true,
            "values": []
          },
          "yaxes": [
            {
              "format": "ms",
              "label": "",
              "logBase": 1,
              "max": null,
              "min": null,
              "show": true
            },
            {
              "format": "short",
              "label": null,
              "logBase": 1,
              "max": null,
              "min": null,
              "show": true
            }
          ]
        },
        {
          "aliasColors": {},
          "bars": false,
          "datasource": "Influx",
          "editable": true,
          "error": false,
          "fill": 1,
          "grid": {},
          "id": 3,
          "legend": {
            "avg": false,
            "current": false,
            "hideEmpty": true,
            "hideZero": true,
            "max": false,
            "min": false,
            "show": true,
            "total": false,
            "values": false
          },
          "lines": true,
          "linewidth": 2,
          "links": [],
          "nullPointMode": "connected",
          "percentage": false,
          "pointradius": 5,
          "points": false,
          "renderer": "flot",
          "seriesOverrides": [],
          "span": 12,
          "stack": false,
          "steppedLine": false,
          "targets": [
            {
              "alias": "$tag_queryid",
              "dsType": "influxdb",
              "groupBy": [
                {
                  "params": [
                    "$interval"
                  ],
                  "type": "time"
                },
                {
                  "params": [
                    "queryid"
                  ],
                  "type": "tag"
                },
                {
                  "params": [
                    "none"
                  ],
                  "type": "fill"
                }
              ],
              "measurement": "stat_statements",
              "policy": "default",
              "query": "SELECT non_negative_derivative(mean(\"calls\"), 1h) FROM \"stat_statements\" WHERE \"dbname\" =~ /^$dbname$/ AND $timeFilter GROUP BY time($interval), \"queryid\" fill(none)",
              "rawQuery": true,
              "refId": "A",
              "resultFormat": "time_series",
              "select": [
                [
                  {
                    "params": [
                      "total_time"
                    ],
                    "type": "field"
                  },
                  {
                    "params": [],
                    "type": "mean"
                  },
                  {
                    "params": [
                      "1h"
                    ],
                    "type": "non_negative_derivative"
                  }
                ]
              ],
              "tags": []
            }
          ],
          "thresholds": [],
          "timeFrom": null,
          "timeShift": null,
          "title": "Calls per query (1h ratio)",
          "tooltip": {
            "msResolution": true,
            "shared": false,
            "sort": 2,
            "value_type": "cumulative"
          },
          "type": "graph",
          "xaxis": {
            "mode": "time",
            "name": null,
            "show": true,
            "values": []
          },
          "yaxes": [
            {
              "format": "short",
              "label": "",
              "logBase": 1,
              "max": null,
              "min": null,
              "show": true
            },
            {
              "format": "short",
              "label": null,
              "logBase": 1,
              "max": null,
              "min": null,
              "show": true
            }
          ]
        }
      ],
      "showTitle": false,
      "titleSize": "h6",
      "height": "250px",
      "repeat": null,
      "repeatRowId": null,
      "repeatIteration": null,
      "collapse": false
    },
    {
      "title": "Dashboard Row",
      "panels": [
        {
          "content": "Brought to you by: <a href=\"http://cybertec.at/en\"><img src=\"http://static.cybertec.at/wp-content/themes/cybertec-optimus/assets/img/logo.png\" alt=\"Cybertec – The PostgreSQL Database Company\"></a>",
          "editable": true,
          "error": false,
          "id": 4,
          "links": [],
          "mode": "html",
          "span": 12,
          "title": "",
          "transparent": true,
          "type": "text"
        }
      ],
      "showTitle": false,
      "titleSize": "h6",
      "height": 250,
      "repeat": null,
      "repeatRowId": null,
      "repeatIteration": null,
      "collapse": false
    }
  ]
}'
);


insert into dashboard (version, slug, title, org_id, created, updated, updated_by, created_by, gnet_id, data)
values (0, 'single-query-details', 'Single query details', 1, now(), now(), 1, 1, 0,
'
{
  "annotations": {
    "list": []
  },
  "description": "For one query",
  "editable": true,
  "gnetId": null,
  "graphTooltip": 0,
  "hideControls": false,
  "id": 5,
  "links": [],
  "rows": [
    {
      "collapse": false,
      "height": 250,
      "panels": [
        {
          "aliasColors": {},
          "bars": false,
          "datasource": null,
          "fill": 1,
          "id": 3,
          "legend": {
            "avg": false,
            "current": false,
            "max": false,
            "min": false,
            "show": true,
            "total": false,
            "values": false
          },
          "lines": true,
          "linewidth": 1,
          "links": [],
          "nullPointMode": "null",
          "percentage": false,
          "pointradius": 5,
          "points": false,
          "renderer": "flot",
          "seriesOverrides": [],
          "span": 12,
          "stack": false,
          "steppedLine": false,
          "targets": [
            {
              "alias": "avg_runtime",
              "dsType": "influxdb",
              "groupBy": [
                {
                  "params": [
                    "$interval"
                  ],
                  "type": "time"
                },
                {
                  "params": [
                    "null"
                  ],
                  "type": "fill"
                }
              ],
              "measurement": "stat_statements",
              "policy": "default",
              "query": "SELECT non_negative_derivative(mean(\"total_time\"), 1h) / non_negative_derivative(mean(\"calls\"), 1h) FROM \"stat_statements\" WHERE \"queryid\" =~ /^$queryid$/ AND $timeFilter GROUP BY time($interval), \"queryid\" fill(null)",
              "rawQuery": true,
              "refId": "A",
              "resultFormat": "time_series",
              "select": [
                [
                  {
                    "params": [
                      "total_time"
                    ],
                    "type": "field"
                  },
                  {
                    "params": [],
                    "type": "mean"
                  },
                  {
                    "params": [
                      "1h"
                    ],
                    "type": "non_negative_derivative"
                  }
                ]
              ],
              "tags": [
                {
                  "key": "queryid",
                  "operator": "=~",
                  "value": "/^$queryid$/"
                }
              ]
            }
          ],
          "thresholds": [],
          "timeFrom": null,
          "timeShift": null,
          "title": "Avg. runtime (ms)",
          "tooltip": {
            "shared": true,
            "sort": 0,
            "value_type": "individual"
          },
          "type": "graph",
          "xaxis": {
            "mode": "time",
            "name": null,
            "show": true,
            "values": []
          },
          "yaxes": [
            {
              "format": "short",
              "label": null,
              "logBase": 1,
              "max": null,
              "min": null,
              "show": true
            },
            {
              "format": "short",
              "label": null,
              "logBase": 1,
              "max": null,
              "min": null,
              "show": true
            }
          ]
        }
      ],
      "repeat": null,
      "repeatIteration": null,
      "repeatRowId": null,
      "showTitle": false,
      "title": "Dashboard Row",
      "titleSize": "h6"
    },
    {
      "collapse": false,
      "height": "250px",
      "panels": [
        {
          "aliasColors": {},
          "bars": false,
          "datasource": null,
          "fill": 1,
          "id": 2,
          "legend": {
            "avg": false,
            "current": false,
            "max": false,
            "min": false,
            "show": true,
            "total": false,
            "values": false
          },
          "lines": true,
          "linewidth": 1,
          "links": [],
          "nullPointMode": "null",
          "percentage": false,
          "pointradius": 5,
          "points": false,
          "renderer": "flot",
          "seriesOverrides": [],
          "span": 12,
          "stack": false,
          "steppedLine": false,
          "targets": [
            {
              "alias": "calls",
              "dsType": "influxdb",
              "groupBy": [
                {
                  "params": [
                    "$interval"
                  ],
                  "type": "time"
                },
                {
                  "params": [
                    "queryid"
                  ],
                  "type": "tag"
                },
                {
                  "params": [
                    "null"
                  ],
                  "type": "fill"
                }
              ],
              "measurement": "stat_statements",
              "policy": "default",
              "refId": "A",
              "resultFormat": "time_series",
              "select": [
                [
                  {
                    "params": [
                      "calls"
                    ],
                    "type": "field"
                  },
                  {
                    "params": [],
                    "type": "mean"
                  },
                  {
                    "params": [
                      "1h"
                    ],
                    "type": "non_negative_derivative"
                  }
                ]
              ],
              "tags": [
                {
                  "key": "queryid",
                  "operator": "=~",
                  "value": "/^$queryid$/"
                }
              ]
            }
          ],
          "thresholds": [],
          "timeFrom": null,
          "timeShift": null,
          "title": "Calls (1h ratio)",
          "tooltip": {
            "shared": true,
            "sort": 0,
            "value_type": "individual"
          },
          "type": "graph",
          "xaxis": {
            "mode": "time",
            "name": null,
            "show": true,
            "values": []
          },
          "yaxes": [
            {
              "format": "short",
              "label": null,
              "logBase": 1,
              "max": null,
              "min": null,
              "show": true
            },
            {
              "format": "short",
              "label": null,
              "logBase": 1,
              "max": null,
              "min": null,
              "show": true
            }
          ]
        },
        {
          "aliasColors": {},
          "bars": false,
          "datasource": null,
          "fill": 1,
          "id": 1,
          "legend": {
            "avg": false,
            "current": false,
            "max": false,
            "min": false,
            "show": true,
            "total": false,
            "values": false
          },
          "lines": true,
          "linewidth": 1,
          "links": [],
          "nullPointMode": "null",
          "percentage": false,
          "pointradius": 5,
          "points": false,
          "renderer": "flot",
          "seriesOverrides": [],
          "span": 12,
          "stack": false,
          "steppedLine": false,
          "targets": [
            {
              "alias": "total_runtime",
              "dsType": "influxdb",
              "groupBy": [
                {
                  "params": [
                    "$interval"
                  ],
                  "type": "time"
                },
                {
                  "params": [
                    "queryid"
                  ],
                  "type": "tag"
                },
                {
                  "params": [
                    "null"
                  ],
                  "type": "fill"
                }
              ],
              "measurement": "stat_statements",
              "policy": "default",
              "refId": "A",
              "resultFormat": "time_series",
              "select": [
                [
                  {
                    "params": [
                      "total_time"
                    ],
                    "type": "field"
                  },
                  {
                    "params": [],
                    "type": "mean"
                  },
                  {
                    "params": [
                      "1h"
                    ],
                    "type": "non_negative_derivative"
                  }
                ]
              ],
              "tags": [
                {
                  "key": "queryid",
                  "operator": "=~",
                  "value": "/^$queryid$/"
                }
              ]
            }
          ],
          "thresholds": [],
          "timeFrom": null,
          "timeShift": null,
          "title": "Total runtime (ms/1h ratio)",
          "tooltip": {
            "shared": true,
            "sort": 0,
            "value_type": "individual"
          },
          "type": "graph",
          "xaxis": {
            "mode": "time",
            "name": null,
            "show": true,
            "values": []
          },
          "yaxes": [
            {
              "format": "short",
              "label": null,
              "logBase": 1,
              "max": null,
              "min": null,
              "show": true
            },
            {
              "format": "short",
              "label": null,
              "logBase": 1,
              "max": null,
              "min": null,
              "show": true
            }
          ]
        }
      ],
      "repeat": null,
      "repeatIteration": null,
      "repeatRowId": null,
      "showTitle": false,
      "title": "Dashboard Row",
      "titleSize": "h6"
    },
    {
      "collapse": false,
      "height": 250,
      "panels": [
        {
          "aliasColors": {},
          "bars": false,
          "datasource": null,
          "fill": 1,
          "id": 4,
          "legend": {
            "avg": false,
            "current": false,
            "max": false,
            "min": false,
            "show": true,
            "total": false,
            "values": false
          },
          "lines": true,
          "linewidth": 1,
          "links": [],
          "nullPointMode": "null",
          "percentage": false,
          "pointradius": 5,
          "points": false,
          "renderer": "flot",
          "seriesOverrides": [],
          "span": 12,
          "stack": false,
          "steppedLine": false,
          "targets": [
            {
              "alias": "sb_hit_ratio",
              "dsType": "influxdb",
              "groupBy": [
                {
                  "params": [
                    "$interval"
                  ],
                  "type": "time"
                },
                {
                  "params": [
                    "null"
                  ],
                  "type": "fill"
                }
              ],
              "measurement": "stat_statements",
              "policy": "default",
              "query": "SELECT non_negative_derivative(mean(\"shared_blks_hit\"), 1h) / (non_negative_derivative(mean(\"shared_blks_hit\"), 1h) + non_negative_derivative(mean(\"shared_blks_read\"), 1h)) * 100 FROM \"stat_statements\" WHERE \"queryid\" =~ /^$queryid$/ AND $timeFilter GROUP BY time($interval), \"queryid\" fill(null)",
              "rawQuery": true,
              "refId": "A",
              "resultFormat": "time_series",
              "select": [
                [
                  {
                    "params": [
                      "shared_blks_hit"
                    ],
                    "type": "field"
                  },
                  {
                    "params": [],
                    "type": "mean"
                  },
                  {
                    "params": [
                      "1h"
                    ],
                    "type": "non_negative_derivative"
                  }
                ]
              ],
              "tags": [
                {
                  "key": "queryid",
                  "operator": "=~",
                  "value": "/^$queryid$/"
                }
              ]
            }
          ],
          "thresholds": [],
          "timeFrom": null,
          "timeShift": null,
          "title": "Shared Buffers Hit Ratio",
          "tooltip": {
            "shared": true,
            "sort": 0,
            "value_type": "individual"
          },
          "type": "graph",
          "xaxis": {
            "mode": "time",
            "name": null,
            "show": true,
            "values": []
          },
          "yaxes": [
            {
              "format": "short",
              "label": null,
              "logBase": 1,
              "max": null,
              "min": null,
              "show": true
            },
            {
              "format": "short",
              "label": null,
              "logBase": 1,
              "max": null,
              "min": null,
              "show": true
            }
          ]
        }
      ],
      "repeat": null,
      "repeatIteration": null,
      "repeatRowId": null,
      "showTitle": false,
      "title": "Dashboard Row",
      "titleSize": "h6"
    },
    {
      "collapse": false,
      "height": 250,
      "panels": [
        {
          "aliasColors": {},
          "bars": false,
          "datasource": null,
          "fill": 1,
          "id": 5,
          "legend": {
            "avg": false,
            "current": false,
            "max": false,
            "min": false,
            "show": true,
            "total": false,
            "values": false
          },
          "lines": true,
          "linewidth": 1,
          "links": [],
          "nullPointMode": "null",
          "percentage": false,
          "pointradius": 5,
          "points": false,
          "renderer": "flot",
          "seriesOverrides": [],
          "span": 12,
          "stack": false,
          "steppedLine": false,
          "targets": [
            {
              "alias": "temp_blks_written",
              "dsType": "influxdb",
              "groupBy": [
                {
                  "params": [
                    "$interval"
                  ],
                  "type": "time"
                },
                {
                  "params": [
                    "queryid"
                  ],
                  "type": "tag"
                },
                {
                  "params": [
                    "null"
                  ],
                  "type": "fill"
                }
              ],
              "measurement": "stat_statements",
              "policy": "default",
              "refId": "A",
              "resultFormat": "time_series",
              "select": [
                [
                  {
                    "params": [
                      "temp_blks_written"
                    ],
                    "type": "field"
                  },
                  {
                    "params": [],
                    "type": "mean"
                  },
                  {
                    "params": [
                      "1h"
                    ],
                    "type": "non_negative_derivative"
                  }
                ]
              ],
              "tags": [
                {
                  "key": "queryid",
                  "operator": "=~",
                  "value": "/^$queryid$/"
                }
              ]
            },
            {
              "alias": "temp_blks_read",
              "dsType": "influxdb",
              "groupBy": [
                {
                  "params": [
                    "$interval"
                  ],
                  "type": "time"
                },
                {
                  "params": [
                    "queryid"
                  ],
                  "type": "tag"
                },
                {
                  "params": [
                    "null"
                  ],
                  "type": "fill"
                }
              ],
              "measurement": "stat_statements",
              "policy": "default",
              "refId": "B",
              "resultFormat": "time_series",
              "select": [
                [
                  {
                    "params": [
                      "temp_blks_read"
                    ],
                    "type": "field"
                  },
                  {
                    "params": [],
                    "type": "mean"
                  },
                  {
                    "params": [
                      "1h"
                    ],
                    "type": "non_negative_derivative"
                  }
                ]
              ],
              "tags": [
                {
                  "key": "queryid",
                  "operator": "=~",
                  "value": "/^$queryid$/"
                }
              ]
            }
          ],
          "thresholds": [],
          "timeFrom": null,
          "timeShift": null,
          "title": "Temp Blocks Read/Write ratio (1h)",
          "tooltip": {
            "shared": true,
            "sort": 0,
            "value_type": "individual"
          },
          "type": "graph",
          "xaxis": {
            "mode": "time",
            "name": null,
            "show": true,
            "values": []
          },
          "yaxes": [
            {
              "format": "short",
              "label": null,
              "logBase": 1,
              "max": null,
              "min": null,
              "show": true
            },
            {
              "format": "short",
              "label": null,
              "logBase": 1,
              "max": null,
              "min": null,
              "show": true
            }
          ]
        }
      ],
      "repeat": null,
      "repeatIteration": null,
      "repeatRowId": null,
      "showTitle": false,
      "title": "Dashboard Row",
      "titleSize": "h6"
    },
    {
      "collapse": false,
      "height": 250,
      "panels": [
        {
          "aliasColors": {},
          "bars": false,
          "datasource": null,
          "fill": 1,
          "id": 6,
          "legend": {
            "avg": false,
            "current": false,
            "max": false,
            "min": false,
            "show": true,
            "total": false,
            "values": false
          },
          "lines": true,
          "linewidth": 1,
          "links": [],
          "nullPointMode": "null",
          "percentage": false,
          "pointradius": 5,
          "points": false,
          "renderer": "flot",
          "seriesOverrides": [],
          "span": 12,
          "stack": false,
          "steppedLine": false,
          "targets": [
            {
              "alias": "blk_read_time",
              "dsType": "influxdb",
              "groupBy": [
                {
                  "params": [
                    "$interval"
                  ],
                  "type": "time"
                },
                {
                  "params": [
                    "queryid"
                  ],
                  "type": "tag"
                },
                {
                  "params": [
                    "null"
                  ],
                  "type": "fill"
                }
              ],
              "measurement": "stat_statements",
              "policy": "default",
              "refId": "A",
              "resultFormat": "time_series",
              "select": [
                [
                  {
                    "params": [
                      "blk_read_time"
                    ],
                    "type": "field"
                  },
                  {
                    "params": [],
                    "type": "mean"
                  },
                  {
                    "params": [
                      "1h"
                    ],
                    "type": "non_negative_derivative"
                  }
                ]
              ],
              "tags": [
                {
                  "key": "queryid",
                  "operator": "=~",
                  "value": "/^$queryid$/"
                }
              ]
            },
            {
              "alias": "blk_write_time",
              "dsType": "influxdb",
              "groupBy": [
                {
                  "params": [
                    "$interval"
                  ],
                  "type": "time"
                },
                {
                  "params": [
                    "queryid"
                  ],
                  "type": "tag"
                },
                {
                  "params": [
                    "null"
                  ],
                  "type": "fill"
                }
              ],
              "measurement": "stat_statements",
              "policy": "default",
              "refId": "B",
              "resultFormat": "time_series",
              "select": [
                [
                  {
                    "params": [
                      "blk_write_time"
                    ],
                    "type": "field"
                  },
                  {
                    "params": [],
                    "type": "mean"
                  },
                  {
                    "params": [
                      "1h"
                    ],
                    "type": "non_negative_derivative"
                  }
                ]
              ],
              "tags": [
                {
                  "key": "queryid",
                  "operator": "=~",
                  "value": "/^$queryid$/"
                }
              ]
            }
          ],
          "thresholds": [],
          "timeFrom": null,
          "timeShift": null,
          "title": "Block Read/Write time ratio (ms/1h)",
          "tooltip": {
            "shared": true,
            "sort": 0,
            "value_type": "individual"
          },
          "type": "graph",
          "xaxis": {
            "mode": "time",
            "name": null,
            "show": true,
            "values": []
          },
          "yaxes": [
            {
              "format": "short",
              "label": null,
              "logBase": 1,
              "max": null,
              "min": null,
              "show": true
            },
            {
              "format": "short",
              "label": null,
              "logBase": 1,
              "max": null,
              "min": null,
              "show": true
            }
          ]
        }
      ],
      "repeat": null,
      "repeatIteration": null,
      "repeatRowId": null,
      "showTitle": false,
      "title": "Dashboard Row",
      "titleSize": "h6"
    }
  ],
  "schemaVersion": 14,
  "style": "dark",
  "tags": [],
  "templating": {
    "list": [
      {
        "allValue": null,
        "current": {
          "tags": [],
          "text": "2584015616",
          "value": "2584015616"
        },
        "datasource": "Influx",
        "hide": 0,
        "includeAll": false,
        "label": null,
        "multi": false,
        "name": "queryid",
        "options": [],
        "query": "show tag values from stat_statements with key = \"queryid\"",
        "refresh": 1,
        "regex": "",
        "sort": 1,
        "tagValuesQuery": "",
        "tags": [],
        "tagsQuery": "",
        "type": "query",
        "useTags": false
      }
    ]
  },
  "time": {
    "from": "now-3h",
    "to": "now"
  },
  "timepicker": {
    "refresh_intervals": [
      "5s",
      "10s",
      "30s",
      "1m",
      "5m",
      "15m",
      "30m",
      "1h",
      "2h",
      "1d"
    ],
    "time_options": [
      "5m",
      "15m",
      "1h",
      "6h",
      "12h",
      "24h",
      "2d",
      "7d",
      "30d"
    ]
  },
  "timezone": "browser",
  "title": "Single query details",
  "version": 0
}'
);
