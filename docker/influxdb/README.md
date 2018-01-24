## Build instructions 

1. Get the latest official InfluxDB Docker sources
    ```
    git clone https://github.com/influxdata/influxdata-docker
    ```

1. Point an env variable to the pgwatch2 source folder
    ```
    PGWATCH2_SOURCE_DIR=~/git/pgwatch2
    ```

1. Apply the "non-root user" patch, change the Influx version as needed, and build the image as usual  
    ```    
    cd influxdata-docker/influxdb/1.4
    git apply $PGWATCH2_SOURCE_DIR/docker/influxdb/non-root-user.patch
    Docker build .
    ```
