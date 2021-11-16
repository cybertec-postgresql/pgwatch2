WITH q_bloat AS (
    SELECT quote_ident(schemaname) || '.' || quote_ident(tblname) as full_table_name,
           bloat_ratio                                            as approx_bloat_percent,
           bloat_size                                             as approx_bloat_bytes,
           fillfactor
    FROM (

/* WARNING: executed with a non-superuser role, the query inspect only tables you are granted to read.
* This query is compatible with PostgreSQL 9.0 and more
*/
             SELECT current_database(),
                    schemaname,
                    tblname,
                    bs * tblpages                  AS real_size,
                    (tblpages - est_tblpages) * bs AS extra_size,
                    CASE
                        WHEN tblpages - est_tblpages > 0
                            THEN 100 * (tblpages - est_tblpages) / tblpages::float
                        ELSE 0
                        END                        AS extra_ratio,
                    fillfactor,
                    CASE
                        WHEN tblpages - est_tblpages_ff > 0
                            THEN (tblpages - est_tblpages_ff) * bs
                        ELSE 0
                        END                        AS bloat_size,
                    CASE
                        WHEN tblpages - est_tblpages_ff > 0
                            THEN 100 * (tblpages - est_tblpages_ff) / tblpages::float
                        ELSE 0
                        END                        AS bloat_ratio,
                    is_na
                    -- , (pst).free_percent + (pst).dead_tuple_percent AS real_frag
             FROM (
                      SELECT ceil(reltuples / ((bs - page_hdr) / tpl_size)) + ceil(toasttuples / 4) AS est_tblpages,
                             ceil(reltuples / ((bs - page_hdr) * fillfactor / (tpl_size * 100))) +
                             ceil(toasttuples / 4)                                                  AS est_tblpages_ff,
                             tblpages,
                             fillfactor,
                             bs,
                             tblid,
                             schemaname,
                             tblname,
                             heappages,
                             toastpages,
                             is_na
                             -- , stattuple.pgstattuple(tblid) AS pst
                      FROM (
                               SELECT (4 + tpl_hdr_size + tpl_data_size + (2 * ma)
                                   - CASE WHEN tpl_hdr_size % ma = 0 THEN ma ELSE tpl_hdr_size % ma END
                                   - CASE
                                         WHEN ceil(tpl_data_size)::int % ma = 0 THEN ma
                                         ELSE ceil(tpl_data_size)::int % ma END
                                          )                    AS tpl_size,
                                      bs - page_hdr            AS size_per_block,
                                      (heappages + toastpages) AS tblpages,
                                      heappages,
                                      toastpages,
                                      reltuples,
                                      toasttuples,
                                      bs,
                                      page_hdr,
                                      tblid,
                                      schemaname,
                                      tblname,
                                      fillfactor,
                                      is_na
                               FROM (
                                        SELECT tbl.oid                                                           AS tblid,
                                               ns.nspname                                                        AS schemaname,
                                               tbl.relname                                                       AS tblname,
                                               tbl.reltuples,
                                               tbl.relpages                                                      AS heappages,
                                               coalesce(toast.relpages, 0)                                       AS toastpages,
                                               coalesce(toast.reltuples, 0)                                      AS toasttuples,
                                               coalesce(substring(
                                                                array_to_string(tbl.reloptions, ' ')
                                                                FROM 'fillfactor=([0-9]+)')::smallint,
                                                        100)                                                     AS fillfactor,
                                               current_setting('block_size')::numeric                            AS bs,
                                               CASE
                                                   WHEN version() ~ 'mingw32' OR version() ~ '64-bit|x86_64|ppc64|ia64|amd64'
                                                       THEN 8
                                                   ELSE 4 END                                                    AS ma,
                                               24                                                                AS page_hdr,
                                               23 + CASE
                                                        WHEN MAX(coalesce(null_frac, 0)) > 0 THEN (7 + count(*)) / 8
                                                        ELSE 0::int END
                                                   +
                                               0                                                                 AS tpl_hdr_size,
                                               sum((1 - coalesce(s.null_frac, 0)) * coalesce(s.avg_width, 1024)) AS tpl_data_size,
                                               bool_or(att.atttypid = 'pg_catalog.name'::regtype)
                                                   OR
                                               count(att.attname) <> count(s.attname)                            AS is_na
                                        FROM pg_attribute AS att
                                                 JOIN pg_class AS tbl ON att.attrelid = tbl.oid
                                                 JOIN pg_namespace AS ns ON ns.oid = tbl.relnamespace
                                                 LEFT JOIN pg_stats AS s ON s.schemaname = ns.nspname
                                            AND s.tablename = tbl.relname AND s.inherited = false AND
                                                                            s.attname = att.attname
                                                 LEFT JOIN pg_class AS toast ON tbl.reltoastrelid = toast.oid
                                        WHERE att.attnum > 0
                                          AND NOT att.attisdropped
                                          AND tbl.relkind IN ('r', 'm')
                                          AND ns.nspname != 'information_schema'
                                        GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
                                        ORDER BY 2, 3
                                    ) AS s
                           ) AS s2
                  ) AS s3
             -- WHERE NOT is_na
         ) s4
)
select /* pgwatch2_generated */
    (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
    (select sum(approx_bloat_bytes) from q_bloat) as approx_table_bloat_b,
    ((select sum(approx_bloat_bytes) from q_bloat) * 100 / pg_database_size(current_database()))::int8 as approx_bloat_percentage
;
