#!/bin/bash

POSTGRES_IMAGE_BASE=postgres # use official Docker images based on Debian

function start_pg {
  if [ -z $1 ] || [ -z $2 ] || [ -z $3 ]; then
    echo "full version, short version and port required. exit"
    exit 1
  fi
  full_ver=$1
  ver=$2
  port=$3

  volume="pg${ver}"
  echo "checking if volume $volume exists for PG ver $full_ver..."
  vol_info=$(docker volume inspect $volume &>/dev/null)
  if [ $? -ne 0 ]; then
    echo "creating volume $volume for PG ver $full_ver..."
    create_vol=$(docker volume create $volume &>/dev/null)
    if [ $? -ne 0 ]; then
      echo "could not create volume for $full_ver:"
      echo "$create_vol"
    fi
  fi

  container_info=$(docker inspect --type container "pg${ver}" &>/dev/null)
  if [ $? -ne 0 ]; then
    echo "starting PG $full_ver on port $port ..."
    echo "docker run -d --name pg${ver} -v $volume:/var/lib/postgresql/data -p $port:5432 $POSTGRES_IMAGE_BASE:$full_ver"
    docker run -d --name "pg${ver}" -v $volume:/var/lib/postgresql/data -p $port:5432 $POSTGRES_IMAGE_BASE:$full_ver &>/tmp/pg-docker-run-all.out
    if [ $? -ne 0 ]; then
      $(grep "is already in use" /tmp/pg-docker-run-all.out &>/dev/null)
      if [[ $? -eq 0 ]] ; then
        echo "$full_ver already running..."
      else
        echo "could not start docker PG $full_ver on port $port"
        exit 1
      fi
    fi
  else
    docker start "pg${ver}"
  fi

  sleep 5

  MASTER_VOL_PATH=$(docker volume inspect --format '{{ .Mountpoint }}' pg$ver)
  if [ $? -ne 0 ] ; then
    echo "could not get master volume info for container pg$ver"
    exit 1
  fi

  # postgresql.conf changes
  echo "shared_preload_libraries='pg_stat_statements'" | sudo tee -a $MASTER_VOL_PATH/postgresql.conf
  echo "track_functions='pl'" | sudo tee -a $MASTER_VOL_PATH/postgresql.conf
  if (( $(echo "$full_ver > 9.1" |bc -l) )); then
    echo "track_io_timing='on'" | sudo tee -a $MASTER_VOL_PATH/postgresql.conf
  fi

  PW2_USER=$(psql -U postgres -h localhost -p $port -XAtc "select count(*) from pg_roles where rolname = 'pgwatch2'")
  if [ $? -ne 0 ] || [ "$PW2_USER" -ne 1 ]; then
    for j in {1..5} ; do # try a few times when starting docker is slow
      psql -U postgres -h localhost -p $port -Xc "create user pgwatch2" &>/dev/null
      if [ $? -eq 0 ]; then
        break
      fi
      sleep 2
    done
    if [ $? -ne 0 ]; then
      echo "could not create pgwatch2 user on docker PG $full_ver on port $port"
      exit 1
    fi
  fi


  if [ "$POSTGRES_IMAGE_BASE" == "postgres" ]; then

    echo "apt update"
    docker exec -it pg${ver} apt update &>/dev/null

    if (( $(echo "$full_ver < 12" |bc -l) )); then
      echo "apt install -y --force-yes postgresql-plpython-${full_ver} python-psutil"
      docker exec -it pg${ver} apt install -y --force-yes postgresql-plpython-${full_ver} python-psutil &>/dev/null
    else
      echo "apt install -y --allow-unauthenticated postgresql-plpython3-${full_ver} python3-psutil"
      docker exec -it pg${ver} apt install -y --allow-unauthenticated postgresql-plpython3-${full_ver} python3-psutil &>/dev/null
    fi
    if [ $? -ne 0 ]; then
        echo "could not install plpython and psutil"
        exit 1
    fi
  else
    echo "skipping install of extra packages as assumed installed on ${POSTGRES_IMAGE_BASE}:${full_ver}..."
  fi  # extra packages

  docker restart "pg${ver}"   # to activate pg_stat_statements
  if [ $? -ne 0 ]; then
      echo "could not restart container pg${ver}"
      exit 1
  fi
}

PGVERS="0 1 2 3 4 5 6 10 11 12"

if [ -n "$1" ]; then
  PGVERS="$1"
fi

for x in $PGVERS ; do

  if [ ${x} -lt 10 ]; then
    ver="9${x}"
    full_ver="9.${x}"
  else
    ver=${x}
    full_ver=${x}
  fi
  port="543${ver}"

  master_running=$(docker ps -q --filter "name=pg${ver}")
  if [ -n "$master_running" ]; then
    echo "PG $full_ver already running"
    continue
  fi

  echo "start_pg $full_ver $ver $port"
  start_pg $full_ver $ver $port

done

echo "done"