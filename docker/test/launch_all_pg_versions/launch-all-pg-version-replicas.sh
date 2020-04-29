#!/bin/bash

POSTGRES_IMAGE_BASE=postgres # use official Docker images based on Debian

MASTER_CONF=$(cat <<-EOF
wal_level=hot_standby
max_wal_senders=2
hot_standby=on
EOF
)

RECOVERY_CONF=$(cat <<-EOF
standby_mode=on
primary_conninfo=
EOF
)


function enable_primary_replication {
  if [ -z $1 ] || [ -z $2 ] || [ -z $3 ]; then
    echo "full version, short version and master port required. exit"
    exit 1
  fi
  full_ver=$1
  ver=$2
  master_port=$3

  needs_restart=0
  volume_name="pg$ver"
  echo "getting master volume $volume_name for PG ver $full_ver..."
  vol_path=$(docker volume inspect --format '{{ .Mountpoint }}' $volume_name)

  if [ $? -ne 0 ]; then
    echo "could not inspect master volume pg$ver for $full_ver:"
    exit 1
  fi
  echo "vol_path: $vol_path"

  HBA_OK=$(sudo grep -q 'host replication all 0.0.0.0/0 trust' $vol_path/pg_hba.conf)
  if [ $? -ne 0 ]; then
	  echo "adding 'host replication all 0.0.0.0/0 trust' to $vol_path/pg_hba.conf"
	  echo "host replication all 0.0.0.0/0 trust" | sudo tee -a $vol_path/pg_hba.conf
	  needs_restart=1
  fi

  if (( $(echo "$full_ver < 10" |bc -l) )); then
	WAL_LEVEL=$(psql -U postgres -h localhost -p $master_port -XAtc "show wal_level")
	if [[ "$WAL_LEVEL" =~ "hot_standby" ]] || [[ "$WAL_LEVEL" =~ "replica" ]] ; then
	  echo "$full_ver master already has replication enabled"
	else
	  echo "enabling replication in $vol_path/postgresql.conf..."
	  echo "$MASTER_CONF" | sudo tee -a $vol_path/postgresql.conf
	  needs_restart=1
	fi
  fi

  if [ "$needs_restart" -gt 0 ]; then
	  echo "restarting pg$ver master container to apply config changes..."
	  docker restart pg$ver
	  if [ $? -ne 0 ]; then
	    echo "could not restart pg$ver master container..."
	    exit 1
	  fi
fi

}

function launch_replica_image {

	if [ -z $1 ] || [ -z $2 ] || [ -z $2 ] ; then
	  echo "full version, short version and master port required. exit"
	  exit 1
	fi

	full_ver=$1
	ver=$2
  repl_port=$3

	# create empty replica volume
	volume_name="pg${ver}-repl"
	echo "checking if volume $volume_name exists for PG replica ver $ver..."
	vol_info=$(docker volume inspect $volume_name)
	if [ $? -ne 0 ]; then
		echo "no volume found..."
	else
		echo "old volume found, dropping..."	# primary_conninfo IP needs changing
		docker volume rm $volume_name &>/tmp/rm_docker_volume.log
		if [ $? -ne 0 ]; then
		  echo "could not drop volume $volume_name for replica $full_ver: `cat /tmp/rm_docker_volume.log`"
		  exit 1
		fi
	fi

	echo "creating volume $volume_name for PG replica ver $full_ver..."
	create_vol=$(docker volume create $volume_name &>/tmp/mk_docker_volume.log)
	if [ $? -ne 0 ]; then
	  echo "could not create volume for replica $full_ver:"
	  exit 1
	fi

 	# get master IP and then freeze
    MASTER_IP=$(docker inspect --type container --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' pg$ver)
    if [ $? -ne 0 ] ; then
      echo "could not get master IP for container pg$ver"
      exit 1
    fi

    MASTER_VOL_PATH=$(docker volume inspect --format '{{ .Mountpoint }}' pg$ver)
    if [ $? -ne 0 ] ; then
      echo "could not get master volume info for container pg$ver"
      exit 1
    fi
    REPLICA_VOL_PATH=$(docker volume inspect --format '{{ .Mountpoint }}' pg${ver}-repl)
    if [ $? -ne 0 ] ; then
      echo "could not get replica volume info for container $ver"
      exit 1
    fi

	echo "pausing pg$ver master image (IP=$MASTER_IP) ..."
	docker pause pg$ver
	if [ $? -ne 0 ]; then
		echo "could not pause master pg$ver image..."
		exit 1
	fi

 	# rsync master DATADIR
 	sudo rsync -a ${MASTER_VOL_PATH}/ $REPLICA_VOL_PATH
 	if [ $? -ne 0 ]; then
 		echo "could not rsync datadir"
 		docker unpause pg$ver
 		exit 1
 	fi

  # recovery.conf
 	if (( $(echo "$full_ver < 12" |bc -l) )); then
 		# create recovery.conf
 		echo "standby_mode='on'" | sudo tee $REPLICA_VOL_PATH/recovery.conf
 		echo "primary_conninfo='host=${MASTER_IP}'" | sudo tee -a $REPLICA_VOL_PATH/recovery.conf
 	else
 		# create standby.signal
 		sudo touch $REPLICA_VOL_PATH/standby.signal
 		echo "primary_conninfo='host=${MASTER_IP}'" | sudo tee -a $REPLICA_VOL_PATH/postgresql.conf
	fi

	# start replica with port+1000
	echo "starting image pg${ver}-repl on port $repl_port ..."
  container_info=$(docker inspect --type container "pg${ver}-repl" &>/dev/null)
  if [ $? -ne 0 ]; then
    echo "docker run -d --name pg${ver}-repl -v ${volume_name}:/var/lib/postgresql/data -p ${repl_port}:5432 -e POSTGRES_HOST_AUTH_METHOD=trust $POSTGRES_IMAGE_BASE:$full_ver"
    docker run -d --name "pg${ver}-repl" -v ${volume_name}:/var/lib/postgresql/data -p ${repl_port}:5432 -e POSTGRES_HOST_AUTH_METHOD=trust ${POSTGRES_IMAGE_BASE}:${full_ver} &>/tmp/pg-docker-run-all.out
    if [ $? -ne 0 ]; then
      $(grep "is already in use" /tmp/pg-docker-run-all.out &>/dev/null)
      if [[ $? -eq 0 ]] ; then
        echo "$full_ver replica already running on port $repl_port..."
        return
      else
        echo "could not start docker PG replica $full_ver on port $repl_port"
        docker unpause pg$ver
        exit 1
      fi
    fi
	else
	  docker start "pg${ver}-repl"
	fi

	sleep 10 # sometimes getting some weird Docker 'port used' problems without larger sleep...

    # unpause master
	docker unpause pg$ver
	if [ $? -ne 0 ]; then
		echo "could not unpause master pg$ver container..."
		exit 1
	fi

  if [ "$POSTGRES_IMAGE_BASE" == "postgres" ]; then

    echo "apt update"
    docker exec -it pg${ver}-repl apt update &>/tmp/apt_update.out

    if (( $(echo "$full_ver < 12" |bc -l) )); then
      echo "apt install -y --force-yes postgresql-plpython-${full_ver} python-psutil"
      docker exec -it pg${ver}-repl apt install -y --force-yes postgresql-plpython-${full_ver} python-psutil &>/tmp/apt_install.out
    else
      echo "apt install -y --allow-unauthenticated postgresql-plpython3-${full_ver} python3-psutil"
      docker exec -it pg${ver}-repl apt install -y --allow-unauthenticated postgresql-plpython3-${full_ver} python3-psutil &>/tmp/apt_install.out
    fi
    if [ $? -ne 0 ]; then
      echo "could not install postgresql-plpython-${full_ver}"
      exit 1
    fi

  else
    echo "skipping install of extra packages as assumed installed on ${POSTGRES_IMAGE_BASE}:${full_ver}..."
  fi  # extra packages

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
  master_port="543${ver}"
  repl_port=$((master_port+1000))

  master_port=$(docker inspect --type container --format='{{(index (index .NetworkSettings.Ports "5432/tcp") 0).HostPort}}' pg$ver)
  echo "enabling replication settings for $full_ver master container ..."
  enable_primary_replication $full_ver $ver $master_port

  repl_image_running=$(docker ps -q --filter "name=pg${ver}-repl")
  if [ -z "$repl_image_running" ]; then

	  echo "creating replica for $full_ver on port $repl_port ..."
	  launch_replica_image $full_ver $ver $repl_port
  else
  	  echo "replica for $full_ver already running"
  fi

done

echo "done"
