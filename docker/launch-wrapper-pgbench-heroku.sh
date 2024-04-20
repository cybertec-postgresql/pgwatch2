#!/usr/bin/env bash

###
### For building the pgbench docker image that simulates queries for the monitored db
###

echo "monitored db pgbench - workload simulator"

#init the db
echo "monitored db pgbench - db init ..."
pgbench ${DATABASE_URL} -s 5 -i 
echo "monitored db pgbench - ... done"

#infinite loop
while : 
do
    echo "monitored db pgbench - workload simulation ..."
    pgbench ${DATABASE_URL} -c 3 -T60
    sleep 10
done


