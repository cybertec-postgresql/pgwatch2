#!/bin/bash

go_on_path=$(which go)
if [ -z "$go_on_path" ] ; then
    export PATH=$PATH:/usr/local/go/bin
fi

./get_dependencies.sh

echo "running 'go build pgwatch2.go prom.go patroni.go logparse.go' ..."

if [ -n "$GIT_TIME" -a -n "$GIT_HASH" ] ; then

  go build -ldflags "-X 'main.GitVersionHash=$GIT_HASH ($GIT_TIME)'" pgwatch2.go prom.go patroni.go logparse.go

elif [ -f build_git_version.txt ] ; then
    # Dockerfile build fills the file with HEAD hash
    go build -ldflags "-X 'main.GitVersionHash=`cat build_git_version.txt`'" pgwatch2.go prom.go patroni.go logparse.go
else

  git_on_path=$(which git)
  # assuming located in pgwatch2 Git repo ...
  if [ -n "$git_on_path" -a -f pgwatch2.go ] ; then
    go build -ldflags "-X 'main.GitVersionHash=`git show -s --format=\"%H (%ci)\" HEAD`'" pgwatch2.go prom.go patroni.go logparse.go
  else
    go build pgwatch2.go prom.go patroni.go logparse.go
  fi

fi
