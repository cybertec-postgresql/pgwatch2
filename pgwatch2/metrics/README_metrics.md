# Metrics folder structure

Following folder structure is expected when adding new metrics:

* Top level metrics folder
  * Metric name (will be stored "as is")
    * Postgres version (the minimal / "from" version where the current query works)
      * metric.sql | metric_su.sql | metric_master.sql | metric_standby.sql ("attributes" can also be combined!)

Helpers ("00_helpers") follows the same pattern and also filename defining "preset configs" must be "preset-configs.yaml".
The top level metrics folder can be located anywhere and must be pointed to via -m /--metrics-folder gatherer params.
