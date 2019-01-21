###
### The "test data" mode can be used to quickly generate test data
### for your chosen data model and planned host count to evaluate I/O
### capacity and query speed for your hardware.
### NB! Test mode does not change the metrics counters, just multiplies data,
### so Grafana dashboards will not be realistic, only "interaction speed"
###

# Before running pgwatch2 daemon in the test data generation mode, for more accurate results
# one should install the helpers manually or just use a superuser (then helpers are created automatically
# in the "ad-hoc mode", which is implicit with "testdata mode"). Also it's recommended to run quite some various
# queries repeatedly on the target host if it's freshly bootstrapped, otherwise "stat_statements" will not contain
# any data. Best to use some live server that is planned to be monitored.

# 1. step - initialize a new schema or drop all existing metrics (for example with public.drop_all_metric_tables())

# 2. step - run the pgwatch daemon in the "test data" mode
# Here we generate 1 week of data for 5 hosts. (could run for a couple of hours!)
/pgwatch2/pgwatch2 --testdata-days 7 --testdata-multiplier 5 --adhoc-config=exhaustive \
    --adhoc-conn-str "host=localhost dbname=monitored_db user=pgwatch2 sslmode=disable" \   # metrics collection target
    --pg-metric-store-conn-str="host=localhost port=5434 dbname=metricsdb user=pgwatch2 sslmode=disable" \ # metrics storage target
    --pg-schema-type=metric-time --verbose

# 3. as current implementation of generating test data a bit slow, if wanting to simulate longer retention / dozens
# of hosts, a python script name "multiply-pg-test-data.py" can be used to quickly multiply metrics on the DB level.
# i.e. generate 1 day of data for 50 hosts and then modify (connect string, multiplication factor) and run the python
# scipt. In general 1 week of data for 1 host for "exhaustive" preset config ~ 1GB data.
