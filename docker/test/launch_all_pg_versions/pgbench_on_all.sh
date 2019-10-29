#!/bin/bash

DURATION=7200
RATE=0.1
SCALE=1
DB=postgres

for ver in 9{0..6} {10..12} ; do

  echo "doing pgbench init for ${ver} ..."
  pgbench -h localhost -U postgres -p "543${ver}" -i $DB

  echo "launching pgbench for ${ver} ..."
  pgbench -h localhost -U postgres -p "543${ver}" -T $DURATION -R $RATE $DB &

done

echo "done. pgbench duration: $DURATION"