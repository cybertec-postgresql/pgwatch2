.. _security:

Security aspects
================

Security can be tightened for most pgwatch2 components quite granularly, but the default values for the Docker image
don't focus on security though but rather on being quickly usable for ad-hoc performance troubleshooting, which is where
the roots of pgwatch2 lie.

Some points on security:

* No noticable impact for the monitored DB is expected with the default settings. For some metrics though can happen that
  the metric reading query (notably "stat_statements") takes some milliseconds, which might be more than an average application
  query. At any time only 2 metric fetching queries are running in parallel on the monitored DBs, with 5s per default
  "statement timeout", except for the "bloat" metrics where it is 15min.

* Starting from v1.3.0 there's a non-root Docker version available (suitable for OpenShift)

* The administrative Web UI doesn't have by default any security. Configurable via env. variables.

* Viewing Grafana dashboards by default doesn't require login. Editing needs a password. Configurable via env. variables.

* InfluxDB has no authentication in Docker setup, so one should just not expose the ports when having concerns.

* Dashboards based on the "stat_statements" metric (Stat Statement Overview / Top) expose actual queries. They are
  mostly stripped of details though, but if no risks can be taken the dashboards (or at least according panels) should be
  deleted. Or as an alternative "stat_statements_no_query_text" or "pg_stat_statements_calls" metrics can be used, which
  don't store query texts.

* Safe certificate connections to Postgres are supported as of v1.5.0

* Encrypting/decrypting passwords stored in the config DB or in YAML config files possible from v1.5.0. An encryption
  passphrase/file needs to be specified then via PW2_AES_GCM_KEYPHRASE / PW2_AES_GCM_KEYPHRASE_FILE. By default passwords
  are stored in plaintext.