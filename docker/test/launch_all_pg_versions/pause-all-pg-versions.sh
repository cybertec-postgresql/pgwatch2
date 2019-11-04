#!/bin/bash

for ver in 9{0..6} {10..12} ; do
  echo "pausing PG $ver ..."
  docker pause "pg${ver}"
  docker pause "pg${ver}-repl"
done
