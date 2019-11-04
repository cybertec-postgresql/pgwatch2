#!/bin/bash

for ver in 9{0..6} {10..12} ; do
  echo "unpausing PG $ver ..."
  docker unpause "pg${ver}"
  docker unpause "pg${ver}-repl"
done
