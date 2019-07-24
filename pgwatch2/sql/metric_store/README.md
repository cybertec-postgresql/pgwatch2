# Rollout sequence

First rollout the below files and then the chosen schema type's folder contents.
* "00_schema_base.sql" - schema type and listing of all known "dbname"-s are stored here
* "01_old_metrics_cleanup_procedures.sql" - used to list all unique dbnames and to delete/drop old metrics by the application (can also be used for manual cleanup).

# Schema types

## metric

A single / separate table for each distinct metric in the "public" schema. No partitioning. Works on all PG versions. Suitable for up to ~25 monitored DBs.

## metric-time

A single "master" table for each distinct metric in the "public" schema + weekly partitions in the "subpartitions" schema. Works on PG 11+ versions. Suitable for up to ~25 monitored DBs. Reduced IO compared to "metric" as old data partitions will be dropped, not deleted.

## metric-dbname-time

A single "master" table for each distinct metric in the "public" schema + 2 level subpartitions ("dbname" + monthly time based) in the "subpartitions" schema. Works on PG 11+ versions. Suitable for 25+ monitored DBs.
NB! Currently minimum effective retention period with this model is 30 days. This will be lifted once PG 12 comes out.

## custom

For cases where the available presets are not satisfactory / applicable. All data inserted into "public.metrics" table and the user is responsible for re-routing with a trigger and possible partition management. In that case all table creations and data cleanup must be performed by the user.
