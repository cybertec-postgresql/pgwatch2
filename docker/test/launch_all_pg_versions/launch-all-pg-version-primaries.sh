#!/bin/bash

function start_pg {
  if [ -z $1 ] || [ -z $2 ]; then
    echo "version and port required. exit"
    exit 1
  fi
  ver=$1
  port=$2

  volume="pg${ver}"
  echo "checking if volume $volume exists for PG ver $ver..."
  vol_info=$(docker volume inspect $volume &>/dev/null)
  if [ $? -ne 0 ]; then
    echo "creating volume $volume for PG ver $ver..."
    create_vol=$(docker volume create $volume &>/dev/null)
    if [ $? -ne 0 ]; then
      echo "could not create volume for $ver:"
      echo "$create_vol"
    fi
  fi

  echo "starting PG $ver on port $port ..."
  docker run --rm -d --name "pg${ver}" -v $volume:/var/lib/postgresql/data -p $port:5432 postgres:$ver &>/tmp/pg-docker-run-all.out
  if [ $? -ne 0 ]; then
    $(grep "is already in use" /tmp/pg-docker-run-all.out &>/dev/null)
    if [[ $? -eq 0 ]] ; then
      echo "$ver already running..."
    else
      echo "could not start docker PG $ver on port $port"
      exit 1
    fi
  fi
  sleep 5

  MASTER_VOL_PATH=$(docker volume inspect --format '{{ .Mountpoint }}' pg$ver)
  if [ $? -ne 0 ] ; then
    echo "could not get master volume info for container pg$ver"
    exit 1
  fi
  echo "shared_preload_libraries='pg_stat_statements'" | sudo tee -a $MASTER_VOL_PATH/postgresql.conf

  PW2_USER=$(psql -U postgres -h localhost -p $port -XAtc "select count(*) from pg_roles where rolname = 'pgwatch2'")
  if [ $PW2_USER -ne 1 ]; then
    for j in {1..5} ; do # try a few times when starting docker is slow
      psql -U postgres -h localhost -p $port -Xc "create user pgwatch2" &>/dev/null
      if [ $? -eq 0 ]; then
        break
      fi
      sleep 1
    done
    if [ $? -ne 0 ]; then
      echo "could not create pgwatch2 user on docker PG $ver on port $port"
      exit 1
    fi
  fi

  echo "apt update"
  docker exec -it pg${ver} apt update &>/dev/null

  if (( $(echo "$ver < 12" |bc -l) )); then
    echo "apt install -y --force-yes postgresql-plpython-${ver} python-psutil"
    docker exec -it pg${ver} apt install -y --force-yes postgresql-plpython-${ver} python-psutil &>/dev/null
  else
    echo "apt install -y --allow-unauthenticated postgresql-plpython3-${ver} python3-psutil"
    docker exec -it pg${ver} apt install -y --allow-unauthenticated postgresql-plpython3-${ver} python3-psutil &>/dev/null
  fi
  if [ $? -ne 0 ]; then
      echo "could not install plpython and psutil"
      exit 1
  fi

  docker restart "pg${ver}"   # to activate pg_stat_statements
  if [ $? -ne 0 ]; then
      echo "could not restart pg${ver}"
      exit 1
  fi
}

i=0
STARTING_PORT=54390
LOW_VERSIONS="9.0 9.1 9.2 9.3 9.4 9.5 9.6"
#LOW_VERSIONS=""

for ver in $LOW_VERSIONS ; do

  repl_image_running=$(docker ps -q --filter "name=pg${ver}")
  if [ -n "$repl_image_running" ]; then
    echo "PG $ver already running"
    i=$((i+1))
    continue
  fi

  start_pg $ver $((STARTING_PORT+i))
  i=$((i+1))

done


i=0
STARTING_PORT=54310
HIGH_VERSIONS="10 11 12"
#HIGH_VERSIONS=

for ver in $HIGH_VERSIONS ; do

  repl_image_running=$(docker ps -q --filter "name=^pg${ver}\$")
  if [ -n "$repl_image_running" ]; then
    echo "PG $ver already running"
    i=$((i+1))
    continue
  fi

  start_pg $ver $((STARTING_PORT+i))
  i=$((i+1))

done

echo "done"