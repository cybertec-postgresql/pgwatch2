#!/bin/bash

command="heroku pg:credentials -a ${WCP_HEROKU_APP_NAME} 2>&1 | grep -v "└─" | grep -v "▸" | grep -w ${WCP_HEROKU_PG_DB_CREDENTIAL} | awk '{print \$NF}'"

while : 
do
    echo "executing $command"
    credential_status=$(eval $command)
    if [ $? -eq 0 ]; then
        echo "credential status [$credential_status]"
        if test "active" = "$credential_status" ; then
            break
        fi
    fi

    sleep 5
done
