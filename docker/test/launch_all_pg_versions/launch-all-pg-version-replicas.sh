#!/bin/bash

#set -e

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
  if [ -z $1 ] || [ -z $2 ] ; then
    echo "version and master port required. exit"
    exit 1
  fi
  ver=$1
  master_port=$2

  needs_restart=0
  volume_name="pg$ver"
  echo "getting volume $volume_name for PG ver $ver..."
  vol_path=$(docker volume inspect --format '{{ .Mountpoint }}' $volume_name)

  if [ $? -ne 0 ]; then
    echo "could not inspect volume for $ver:"
    echo "$vol_path"
    exit 1
  fi

  HBA_OK=$(sudo grep -q 'host replication all 0.0.0.0/0 trust' $vol_path/pg_hba.conf)
  if [ $? -ne 0 ]; then
	  echo "adding 'host replication all 0.0.0.0/0 trust' to $vol_path/pg_hba.conf"
	  echo "host replication all 0.0.0.0/0 trust" | sudo tee -a $vol_path/pg_hba.conf
	  needs_restart=1
  fi

  if (( $(echo "$ver < 10" |bc -l) )); then
	WAL_LEVEL=$(psql -U postgres -h localhost -p $master_port -XAtc "show wal_level")
	if [[ "$WAL_LEVEL" =~ "hot_standby" ]] || [[ "$WAL_LEVEL" =~ "replica" ]] ; then
	  echo "$ver master already has replication enabled"
	else
	  echo "enabling replication in $vol_path/postgresql.conf..."
	  echo "$MASTER_CONF" | sudo tee -a $vol_path/postgresql.conf
	  needs_restart=1
	fi
  fi

  if [ "$needs_restart" -gt 0 ]; then
	  echo "restarting pg$ver master image to apply config changes..."
	  docker restart pg$ver
	  if [ $? -ne 0 ]; then
	    echo "could not restart pg$ver master image..."
	    exit 1
	  fi
fi

}

function launch_replica_image {

	if [ -z $1 ] || [ -z $2 ] ; then
	  echo "ver and port needed"
	  exit 1
	fi

	ver=$1
    repl_port=$2

	# create empty replica volume
	volume_name="pg${ver}-repl"
	echo "checking if volume $volume_name exists for PG replica ver $ver..."
	vol_info=$(docker volume inspect $volume_name)
	if [ $? -ne 0 ]; then
		echo "no volume found..."
	else
		echo "old volume found, dropping..."	# primary_conninfo IP needs changing
		docker volume rm $volume_name &>/dev/null
		if [ $? -ne 0 ]; then
		  echo "could not drop volume $volume_name for replica $ver:"
		  exit 1
		fi
	fi

	echo "creating volume $volume_name for PG replica ver $ver..."
	create_vol=$(docker volume create $volume_name &>/dev/null)
	if [ $? -ne 0 ]; then
	  echo "could not create volume for replica $ver:"
	  exit 1
	fi

 	# get master IP and then freeze
    MASTER_IP=$(docker inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' pg$ver)
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

  echo "shared_preload_libraries='pg_stat_statements'" | sudo tee -a $REPLICA_VOL_PATH/postgresql.conf
 	if (( $(echo "$ver < 12" |bc -l) )); then
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
	docker run --rm -d --name "pg${ver}-repl" -v $volume_name:/var/lib/postgresql/data -p $repl_port:5432 postgres:$ver &>/tmp/pg-docker-run-all.out
	#docker run --rm --name "pg${ver}-repl" -v $volume_name:/var/lib/postgresql/data -p $repl_port:5432 postgres:$ver
	if [ $? -ne 0 ]; then
		$(grep "is already in use" /tmp/pg-docker-run-all.out &>/dev/null)
		if [[ $? -eq 0 ]] ; then
		  echo "$ver replica already running on port $repl_port..."
		else
		  echo "could not start docker PG replica $ver on port $repl_port"
		  docker unpause pg$ver
		  exit 1
		fi
	fi
	sleep 5

    # unpause master
	docker unpause pg$ver
	if [ $? -ne 0 ]; then
		echo "could not unpause master pg$ver container..."
		exit 1
	fi

	# plpython
	echo "apt update"
	docker exec -it pg${ver}-repl apt update &>/dev/null

	if (( $(echo "$ver < 12" |bc -l) )); then
		echo "apt install -y --force-yes postgresql-plpython-${ver} python-psutil"
		docker exec -it pg${ver}-repl apt install -y --force-yes postgresql-plpython-${ver} python-psutil &>/dev/null
	else
		echo "apt install -y --allow-unauthenticated postgresql-plpython3-${ver} python3-psutil"
		docker exec -it pg${ver}-repl apt install -y --allow-unauthenticated postgresql-plpython3-${ver} python3-psutil &>/dev/null
	fi
	if [ $? -ne 0 ]; then
	  echo "could not install postgresql-plpython-${ver}"
	  exit 1
	fi
}


PG_VERSIONS="9.0 9.1 9.2 9.3 9.4 9.5 9.6 10 11 12"
#PG_VERSIONS="12"
for ver in $PG_VERSIONS ; do

  master_port=$(docker inspect --format='{{(index (index .NetworkSettings.Ports "5432/tcp") 0).HostPort}}' pg$ver)
  echo "enabling replication settings for $ver master container ..."
  enable_primary_replication $ver $master_port

  repl_image_running=$(docker ps -q --filter "name=pg${ver}-repl")
  if [ -z "$repl_image_running" ]; then
	  repl_port=$((master_port+1000))
	  echo "creating replica for $ver on port $repl_port ..."
	  launch_replica_image $ver $repl_port
  else
  	  echo "replica for $ver already running"
  fi

done

echo "done"
