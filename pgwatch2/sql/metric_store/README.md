# Rollout sequence

First the "schema_base.sql" should be rolled out and then the chosen schema type's folder contents

# Schema types

## metric

A single / separate table for each distinct metric in the "public" schema. No partitioning. Works on all PG versions. Suitable for up to ~25 monitored DBs.

## metric-time

A single "master" table for each distinct metric in the "public" schema + weekly partitions in the "subpartitions" schema. Works on PG 11+ versions. Suitable for up to ~25 monitored DBs. Reduced IO compared to "metric" as old data partitions will be dropped, not deleted.

## metric-dbname-time

A single "master" table for each distinct metric in the "public" schema + 2 level subpartitions ("dbname" + monthly time based) in the "subpartitions" schema. Works on PG 11+ versions. Suitable for 25+ monitored DBs.

## custom

For cases where the available presets are not satisfactory / applicable. All data inserted into "public.metrics" table and the user is responsible for re-routing with a trigger and possible partition management. In that case all table creations and data cleanup must be performed by the user.
