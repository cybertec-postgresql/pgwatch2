#!/bin/bash

echo "dropping old containers if any ..."
for x in pw2 pw2pg pw2nr ; do
  docker stop $x &>/dev/null
  docker rm $x &>/dev/null
done

echo "docker run -d --rm --name pw2 -p 9432:5432 -p 9000:3000 -p 9080:8080  -p 9086:8086 -e PW2_TESTDB=1 cybertec/pgwatch2:latest"
docker run -d --rm --name pw2 -p 9432:5432 -p 9000:3000 -p 9080:8080  -p 9086:8086 -e PW2_TESTDB=1 cybertec/pgwatch2:latest
sleep 10
echo "run -d --rm --name pw2pg -p 9433:5432 -p 9001:3000 -p 9081:8080 -e PW2_TESTDB=1 cybertec/pgwatch2-postgres:latest"
docker run -d --rm --name pw2pg -p 9433:5432 -p 9001:3000 -p 9081:8080 -e PW2_TESTDB=1 cybertec/pgwatch2-postgres:latest
sleep 10
echo "run -d --rm --name pw2nr -p 9434:5432 -p 9002:3000 -p 9082:8080 -p 9087:8086 -e PW2_TESTDB=1 cybertec/pgwatch2-nonroot:latest"
docker run -d --rm --name pw2nr -p 9434:5432 -p 9002:3000 -p 9082:8080 -p 9087:8086 -e PW2_TESTDB=1 cybertec/pgwatch2-nonroot:latest

sleep 30

PGPASSWORD=pgwatch2admin
echo "pgbench -i -s10 ..."
pgbench -i -s10 --unlogged -U pgwatch2 -p 9432 pgwatch2 &>/dev/null
pgbench -i -s10 --unlogged -U pgwatch2 -p 9433 pgwatch2 &>/dev/null
pgbench -i -s10 --unlogged -U pgwatch2 -p 9434 pgwatch2 &>/dev/null

echo "generating some light load for 10min ..."
pgbench -T600 -R1 -U pgwatch2 -p 9432 pgwatch2 &
pgbench -T600 -R1 -U pgwatch2 -p 9433 pgwatch2 &
pgbench -T600 -R1 -U pgwatch2 -p 9434 pgwatch2 &

wait
