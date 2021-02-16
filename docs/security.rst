.. _security:

Security aspects
================

General security information
----------------------------

Security can be tightened for most pgwatch2 components quite granularly, but the default values for the Docker image
don't focus on security though but rather on being quickly usable for ad-hoc performance troubleshooting, which is where
the roots of pgwatch2 lie.

Some points on security:

* Starting from v1.3.0 there's a non-root Docker version available (suitable for OpenShift)

* The administrative Web UI doesn't have by default any security. Configurable via env. variables.

* Viewing Grafana dashboards by default doesn't require login. Editing needs a password. Configurable via env. variables.

* InfluxDB has no authentication in Docker setup, so one should just not expose the ports when having concerns.

* Dashboards based on the "stat_statements" metric (Stat Statement Overview / Top) expose actual queries.

  They should be "mostly" stripped of details though and replaced by placeholders by Postgres, but if no risks can be taken
  such dashboards (or at least according panels) should be deleted. Or as an alternative the "stat_statements_no_query_text"
  and "pg_stat_statements_calls" metrics could be used, which don't store query texts in the first place.

* Safe certificate connections to Postgres are supported as of v1.5.0

  According *sslmode* (verify-ca, verify-full) and cert file paths need to be specified then on Web UI "/dbs" page or in
  the YAML config.

* Encryption / decryption of connection string passwords stored in the config DB or in YAML config files

  By default passwords are stored in plaintext but as of v1.5 it's possible to use an encryption passphrase, or a file
  with the passphrase in it,  via *\-\-aes-gcm-keyphrase / \-\-aes-gcm-keyphrase-file* or *PW2_AES_GCM_KEYPHRASE / PW2_AES_GCM_KEYPHRASE_FILE* parameters.
  If using the Web UI to store connection info, the same encryption key needs to be specified for both the Web UI and the
  gatherer. If using YAML configs then encrypted passwords can be generated using the *--aes-gcm-password-to-encrypt* flag
  for embedding in YAML.

  Note that although pgwatch2 can handle password security, in many cases it's better to still use the standard LibPQ *.pgpass*
  file to store passwords.

Launching a more secure Docker container
----------------------------------------

Some common sense security is built into default Docker images for all components but not actived by default. A sample
command to launch pgwatch2 with following security "checkpoints" enabled:

#. HTTPS for both Grafana and the Web UI with self-signed certificates
#. No anonymous viewing of graphs in Grafana
#. Custom user / password for the Grafana "admin" account
#. No anonymous access / editing over the admin Web UI
#. No viewing of internal logs of components running inside Docker
#. Password encryption for connect strings stored in the Config DB

::

    docker run --name pw2 -d --restart=unless-stopped \
      -p 3000:3000 -p 8080:8080 \
      -e PW2_GRAFANASSL=1 -e PW2_WEBSSL=1 \
      -e PW2_GRAFANANOANONYMOUS=1 -e PW2_GRAFANAUSER=myuser -e PW2_GRAFANAPASSWORD=mypass \
      -e PW2_WEBNOANONYMOUS=1 -e PW2_WEBNOCOMPONENTLOGS=1 \
      -e PW2_WEBUSER=myuser -e PW2_WEBPASSWORD=mypass \
      -e PW2_AES_GCM_KEYPHRASE=qwerty \
      cybertec/pgwatch2-postgres

NB! For custom installs it's up to the user though. A hint - Docker *launcher* files can also be inspected to see
which config parameters are being touched.
