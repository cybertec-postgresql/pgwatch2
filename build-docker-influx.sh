docker build --build-arg GIT_TIME="`git show -s --format=\"%ci\" HEAD`" --build-arg GIT_HASH=`git show -s --format="%H" HEAD` -t cybertec/pgwatch2:latest .
