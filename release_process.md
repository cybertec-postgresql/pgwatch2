= Release process =


1. Build the packages and set up pgwatch2 on a new fresh VM, also adding
a couple of DBs to monitor.

goreleaser --snapshot --skip-publish --rm-dist

For that one needs to install goreleaser and nfpm. If all was good I've
just uploaded the tar, deb and rpm files to Github.


2. Build docker images. There are 4 older actively maintained images + 1
newer.

Main images:

# cybertec/pgwatch2 
the original InfluxDB metric storage based full
container depicted on the architecture image

# cybertec/pgwatch2-nonroot
later added InfluxDB metric storage based
full container with a normal user, ie cannot install new tools in the
container

# cybertec/pgwatch2-postgres
later added Postgres based storage, should
become the main focus

# cybertec/pgwatch2-daemon 
only the metrics collector + metric definitions. can btw used also
conveniently instead of the DEB / RPM install from command line,
especially for "ad-hoc" mode

# cybertec/pgwatch2-db-bootstrapper
this is the newest image, used just to roll out the Config DB or Metrics DB 
schema for PG storage. It was not versioned before, just the "latest" tag 
but now from 1.8.5 also versioned and should be pushed.

3. Test Docker images. For that there's  a
smoke_test_all_latest_images.sh script in the "docker" folder that does
some basic checks.

4. Push images to Docker hub (https://hub.docker.com/u/cybertec).

Credentials are in Bitkeeper I think or ask from Lorenz.

For pushing I also have a small helper script: pw2_push_all_tag

```sh
if [ -z "$1" ] ; then
   echo "usage: push_tagged 1.x.x"
else
   TAG="$1"
   IMAGES="cybertec/pgwatch2-postgres cybertec/pgwatch2
cybertec/pgwatch2-nonroot cybertec/pgwatch2-daemon
cybertec/pgwatch2-db-boostrapper"
   for IMAGE in $IMAGES ; do
     echo "pushing ${IMAGE}:${TAG} ..."
     sleep 5
     docker push ${IMAGE}:${TAG}
   done
fi
```

5. Update the demo site - https://demo.pgwatch.com/

```bash
$ ssh root@demo.pgwatch.com
```

How I've done it is that I've created a new container in parallel to the
running one with new volumes, and then at some just stopped the old and
restarted the new one with original ports.

For SSL there's some let's encrypt daemon running which I believe was
registered with my Gmail account so if the cert at some day is
invalidate I recommend setting up a fresh certbot installation.

For Grafana one besides mounting the certs ( -v
/etc/letsencrypt:/etc/letsencrypt ) one also needs to edit the
grafana.ini to use the certs so take a look at /etc/grafana/grafana.ini
from inside the container to see how it's done. One could also basically
map that file over a volume so less work in future.

See the "history" how the container is exactly launched but basically
it's something like that:

```s
docker run -d --restart unless-stopped -p 127.0.0.1:5432:5432 -p
443:3000 -p 8081:8081     -e PW2_TESTDB=1 -e PW2_GRAFANASSL=1 -e
PW2_GRAFANAPASSWORD=seitselehma777     -v pg181:/var/lib/postgresql -v
grafana181:/var/lib/grafana -v pw181:/pgwatch2/persistent-config -v
/etc/letsencrypt:/etc/letsencrypt     --name pw2-1.8.1-2
cybertec/pgwatch2-postgres:1.8.1
```

Note that I also have some Cronjobs to simulate some load, so that the
charts would not look like a straight line :)

```s
# m h  dom mon dow   command
*/5 * * * * /usr/bin/pgbench-gen-load.sh
* * * * * psql -h localhost -p5432 -U pgwatch2 -c "select count(bid) from pgbench_accounts"  pgwatch2
#* * * * * psql -h localhost -p5433 -U pgwatch2 -c "select count(bid) from pgbench_accounts"  pgwatch2
* * * * * psql -h localhost -p5432 -U pgwatch2 -c "select pg_sleep(50)" pgwatch2
*/2 * * * * psql -h localhost -p5432 -U pgwatch2 -c "explain analyze select * from pgbench_accounts order by random()" pgwatch2
```

6. Updating the documentation site https://pgwatch2.readthedocs.io/

All major changes should be of course also documented. The building
happens automatically on Git push via readthedocs but you'd want to
install sphinx also locally to test out bigger changes and see warnings.
"make html" is the command from the pgwatch2 "docs" folder.

I've now sent an invite to your email so please click on the link to
create an account. Give me a ping once all is good, I'll make yours the
primary address then :)