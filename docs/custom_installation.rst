.. _custom_installation:

Installing without Docker
=========================

Config store
------------


Below are sample steps to do a custom install from scratch using Postgres for the pgwatch2 configuration DB, metrics DB and
Grafana config DB. NB! pgwatch2 config can also be stored YAML and Grafana can use embedded Sqlite DB so technically only
DB that is absolutely needed is the metrics storage DB, here Postgres (alternatives - InfluxDB, Prometheus, Graphite).
All examples assuming Ubuntu.

1. Install Postgres.

    The latest major version if possible, but minimally v11 is recommended for the metrics DB due to
    partitioning speedup improvements and also older versions were missing some default JSONB casts so that some Grafana dashboards
    need adjusting otherwise.

    To get the latest Postgres versions PGDG repos are to be preferred over default disto repos:
     * For Debian / Ubuntu based systems: https://wiki.postgresql.org/wiki/Apt
     * For CentOS / RedHat based systems: https://yum.postgresql.org/

    ```
    sudo apt install postgresql
    ```
    Default port: 5432

    1.a. Alternative flow for InfluxDB metrics storage (ignore for Postgres):
    ```
    INFLUX_LATEST=$(curl -so- https://api.github.com/repos/influxdata/influxdb/tags | grep -Eo '"v[0-9\.]+"' | grep -Eo '[0-9\.]+' | sort -nr | head -1)
    wget https://dl.influxdata.com/influxdb/releases/influxdb_${INFLUX_LATEST}_amd64.deb
    sudo dpkg -i influxdb_${INFLUX_LATEST}_amd64.deb
    ```

    Take a look/edit the Influx config at /etc/influxdb/influxdb.conf and it's recommend to create also a separate limited
    login user e.g. "pgwatch2" to be used by the metrics gathering daemon to store metrics. See [here](https://docs.influxdata.com/influxdb/latest/administration/config/)
    on configuring InfluxDB and [here](https://docs.influxdata.com/influxdb/latest/administration/authentication_and_authorization/)
    for creating new users.

    Default port for the API: 8086

2. Create needed DB-s, roles and config tables for the pgwatch2 config and metrics DB-s and Grafana DB.

    2.1. Create an user and a DB to hold Grafana config
    ```
    psql -c "create user pgwatch2_grafana password 'xyz'"
    psql -c "create database pgwatch2_grafana owner pgwatch2_grafana"
    ```

    2.2. Create an User and a DB to hold pgwatch2 config
    ```
    psql -c "create user pgwatch2 password 'xyz'"
    psql -c "create database pgwatch2 owner pgwatch2"
    ```

    2.3 Roll out the pgwatch2 config schema (will hold connection strings of DB-s to be monitored + metric definitions)
    ```
    psql -f pgwatch2/sql/config_store/config_store.sql pgwatch2
    psql -f pgwatch2/sql/config_store/metric_definitions.sql pgwatch2
    ```

    2.4 Create an user and a DB to hold pgwatch2 gathered metrics
    ```
    psql -c "create database pgwatch2_metrics owner pgwatch2"
    ```

    2.5 Roll out the pgwatch2 metrics storage schema. Here one should 1st think how many databases will be monitored and
    choose an according metrics storage schema - there are a couple of different options described [here](https://github.com/cybertec-postgresql/pgwatch2/tree/master/pgwatch2/sql/metric_store).
    For a smaller amount (a couple dozen) of monitored DBs the "metric-time" is a good choice.

    NB! Default retention for Postgres storage is 2 weeks! To change, use the --pg-retention-days parameter for the gatherer (step 5).
    ```
    psql -f pgwatch2/sql/metric_store/roll_out_metric_time.sql pgwatch2_metrics
    ```

3. Install Grafana

    ```
    GRAFANA_LATEST=$(curl -so- https://api.github.com/repos/grafana/grafana/tags | grep -Eo '"v[0-9\.]+"' | grep -Eo '[0-9\.]+' | sort -nr | head -1)
    wget https://s3-us-west-2.amazonaws.com/grafana-releases/release/grafana_${GRAFANA_LATEST}_amd64.deb
    sudo dpkg -i grafana_${GRAFANA_LATEST}_amd64.deb
    ```
    Default port: 3000

    2.1. Configure Grafana config to use our pgwatch2_grafana DB

    Place something like below in the "[database]" section of /etc/grafana/grafana.ini

    ```
    [database]
    type = postgres
    host = my-postgres-db:5432
    name = pgwatch2_grafana
    user = pgwatch2_grafana
    password = xyz
    ```

    Taking a look at [server], [security] and [auth*] sections is also recommended.

    2.2. Set up the Influx datasource as default

    Use the Grafana UI (Admin -> Data sources) or adjust and execute the "pgwatch2/bootstrap/grafana_datasource.sql"

    2.3. Add pgwatch2 predefined dashboards to Grafana

    This could be done by importing the JSON-s from the "grafana_dashboards" folder manually (Import Dashboard from the Grafana
    top menu) or via the Docker bootstrap script (pgwatch2/bootstrap/set_up_grafana_dashboards.sh). Script needs some adjustment
    for connect data and file paths though and also the "grafana_datasource.sql" part should be commented out if already
    executed in the previous step.

    2.4. Optionally install also Grafana plugins

    Currently only one pre-configured dashboard (Biggest relations treemap) use an extra plugin. If needed install via:
    ```
    grafana-cli plugins install savantly-heatmap-panel
    ```

4. Install Python 3 and start the Web UI

    NB! The Web UI is not strictly required but makes life a lot easier. Technically it would be fine also to manage connection
    strings of the monitored DB-s directly in the "pgwatch2.monitored_db" table and add/adjust metrics in the "pgwatch2.metric" table,
    and "preset configs" in the "pgwatch2.preset_config" table.

    ```
    # first we need Python 3 and "pip" - the Python package manager
    sudo apt install python3 python3-pip
    sudo pip3 install -U -r webpy/requirements.txt
    ```

    4.0. Optional step: for use cases where exposing component (Grafana, Postgres, Influx, gatherer daemon, Web UI itself) logs via the
    Web UI could be benficial, one should also change the log file paths hardcoded in the SERVICES variable of the pgwatch2.py source
    file. Defaults are set to work with the Docker image.

    4.1. Start the Web UI
    ```
    cd webpy
    python3 web.py  # with defaults - PG config DB and Influx metrics DB on localhost
    # OR with PG config DB and metrics DB on localhost
    python3 web.py --datastore=postgres --pg-metric-store-conn-str="dbname=pgwatch2_metrics user=pgwatch2"
    ```
    Default port for the Web UI: 8080. See web.py --help for all options.

    4.2. Configure DB-s to monitor from "/dbs" page

    NB! To get most out of your metrics some wrappers/extensions are required on the DB-s under monitoring.
    See section [Steps to configure your database for monitoring](https://github.com/cybertec-postgresql/pgwatch2#steps-to-configure-your-database-for-monitoring) on
    setup information.

    4.3. Exposing component logs (optional)

    Note that if the "/logs" endpoint is wanted also in the custom setup mode then then some actual code changes
    are needed to specify where logs of all components are situated - see top of the pgwatch2.py file for that. Default
    settings only make sure things work with the Docker images.

5. Install Go and compile the gatherer

    NB! There are pre-built binaries DEB / RPM / Tar packages also avaialble on the "releases" tab so this step is not
    really mandatory if maximum control or code changes are not required.

    Check for the latest Go version from https://golang.org/dl/

    ```
    # install Go (latest version preferably, but at least 1.10)
    wget https://dl.google.com/go/go1.11.linux-amd64.tar.gz
    tar -C /usr/local -xzf go1.11.linux-amd64.tar.gz
    export PATH=$PATH:/usr/local/go/bin

    # compile the gatherer daemon
    cd pgwatch2
    ./build_gatherer.sh
    # an executable named "pgwatch2" should be generated ...
    ```

      5.1. Run the gatherer

    ```
    ./pgwatch2 --host=my-postgres-db --user=pgwatch2 --password=xyz  \
        --ihost=my-influx-db --iuser=pgwatch2 --ipassword=xyz

    # for all starting options run "./pgwatch2 --help"
    ```

    Congrats! Now the metrics should start flowing in and after some minutes one should already see some graphs in Grafana.

6. Install and configure SystemD init scripts for the Gatherer and the Web UI [here](https://github.com/cybertec-postgresql/pgwatch2/tree/master/pgwatch2/startup-scripts) and [here](https://github.com/cybertec-postgresql/pgwatch2/tree/master/webpy/startup-scripts) or make sure to hatch up some "init scripts" so that the pgwatch2 daemon and the Web UI would be started automatically when the system reboots. For externally packaged components (Grafana, Influx, Postgres) it should be the case already.
