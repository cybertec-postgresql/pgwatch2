#!/bin/bash

for ver in 9.{0..6} {10..12} ; do
  docker pull postgres:$ver
done
