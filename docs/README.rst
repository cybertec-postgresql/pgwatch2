========
Introduction
========


pgwatch2 is a flexible PostgreSQL-specific monitoring solution, relying on Grafana dashboards for the UI part. It supports monitoring
of almost all metrics for Postgres versions 9.0 to 13 out of the box and can be easily extended to include custom metrics.
At the core of the solution is the metrics gathering daemon written in Go, with many option to configure the aggressiveness of
monitoring, types of metrics storage and the display the metrics.

Quick start
===========

For the fastest setup experience Docker images are provided via Docker Hub (if new to Docker start `here <https://docs.docker.com/get-started/>`_).
For custom setups see the :ref:`Custom installations <custom_installations>` paragraph below or turn to the pre-built DEB / RPM / Tar
packages on the Github Releases `page <https://github.com/cybertec-postgresql/pgwatch2/releases>`_.

Launching the latest pgwatch2 Docker image with built-in InfluxDB metrics storage DB:

::

    # run the latest Docker image, exposing Grafana on port 3000 and the administrative web UI on 8080
    docker run -d -p 3000:3000 -p 8080:8080 -e PW2_TESTDB=true --name pw2 cybertec/pgwatch2

After some minutes you could open the `"db-overview" <http://127.0.0.1:3000/dashboard/db/db-overview>`_ dashboard and start
looking at metrics in Grafana. For defining your own dashboards or making changes you need to log in as admin (default
user/password: admin/pgwatch2admin).

NB! If you don't want to add the "test" database (the pgwatch2 configuration DB holding connection strings to monitored DBs
and metric definitions) to the monitoring remove the PW2_TESTDB env variable.
