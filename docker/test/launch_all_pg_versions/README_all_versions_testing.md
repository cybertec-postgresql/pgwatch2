# Docker launching scripts for metrics testing

In this folder are scripts to launch Docker containers for all supported Postgres versions (9.0-12), optionally with replicas.
By default standard Docker images are used with the following additions:

* a volume named "pg$ver" is created
* PL/Python is installed
* "psutil" Python package is installed
* "pg_stat_statements" extension is activated

# PG version to container name and port mappings

Postgres v9.0 container is launched under name "pg90" and exposed port will be 54390, i.e. following mapping is used:

```
for ver in {0..6} {10..12}  ; do
  if [ ${ver} -lt 10 ]; then
    echo "PG v9.${ver} => container: pg9${ver}, port: 5439${ver}"
  else
    echo "PG v${ver} => container: pg${ver}, port: 543${ver}"
  fi
done

PG v9.0 => container: pg90, port: 54390
PG v9.1 => container: pg91, port: 54391
PG v9.2 => container: pg92, port: 54392
PG v9.3 => container: pg93, port: 54393
PG v9.4 => container: pg94, port: 54394
PG v9.5 => container: pg95, port: 54395
PG v9.6 => container: pg96, port: 54396
PG v10 => container: pg10, port: 54310
PG v11 => container: pg11, port: 54311
PG v12 => container: pg12, port: 54312
```

Replica port = Master port + 1000

# Speeding up testing

If there's a need to constantly launch all images with replicas, it takes quite some time for "apt update/install" so it
makes sense to do it once and then commit the changed containers into new images that can be then re-used, and adjust the
POSTGRES_IMAGE_BASE variable in both launch scripts.

```
for x in {0..6} {10..12} ; do
  if [ ${x} -lt 10 ]; then
    ver="9${x}"
    pgver="9.${x}"
  else
    ver="${x}"
    pgver="${x}"
  fi
  echo "docker commit pg${ver} postgres-pw2:${pgver}"
  docker commit pg${ver} postgres-pw2:${pgver}
done
```
