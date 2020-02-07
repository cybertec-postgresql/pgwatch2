Metric fetching helpers are normal PL/pgSQL or PL/Python stored procedures that provide OS level information which is not
available at all with normal PostgreSQL means (as Postgres is pretty much oblivious on OS details) or some security
sensitive internal statistics (like query texts) that are superuser restricted. For the latter case though, starting from
version 10, there's a special "pg_monitor" system grant available to be used for exactly such monitoring purposes. Then
helpers are only needed for OS-level metrics.

To make rolling out helpers easier there's a small Python script provided - rollout_helper.py, that contacts the config DB
to find all "DBs to be monitored" and then tries to roll out all helpers (if master) and gives execute grants to the monitoring user.
