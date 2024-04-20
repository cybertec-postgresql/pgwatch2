#!/bin/bash

# before creating any credentials check for HA status otherwise credentials cannot be created 
command="heroku pg:info ${WFHA_HEROKU_PG_DB} -a ${WFHA_HEROKU_APP_NAME} | grep \"HA Status:\" | awk -F':' '{print \$2}'| sed 's/^[[:space:]]*//g'"

while : 
do
    echo "executing $command"
    ha_status=$(eval $command)
    if [ $? -eq 0 ]; then
        echo "HA status [$ha_status]"
        # for HA DBs waiting for "Available" otherwise the "HA Status:" attribute is missing 
        if test "Available" = "$ha_status" || test -z "$ha_status" ; then
            break
        fi
    fi

    sleep 60
done