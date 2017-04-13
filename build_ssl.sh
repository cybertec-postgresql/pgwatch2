#!/bin/bash

pushd pgwatch2
./get_dependencies.sh
go build pgwatch2.go
popd

git rev-parse HEAD > build_git_version.txt

docker build -f Dockerfile-Self-Signed-SSL .
