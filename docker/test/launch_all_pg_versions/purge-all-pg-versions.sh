#!/bin/bash

for ver in 9{0..6} {10..12} ; do
  echo "stopping PG $ver ..."
  docker stop "pg${ver}"
  docker stop "pg${ver}-repl"

  echo "removing volumes for PG $ver ..."
  docker volume rm "pg${ver}"
  docker volume rm "pg${ver}-repl"
done
