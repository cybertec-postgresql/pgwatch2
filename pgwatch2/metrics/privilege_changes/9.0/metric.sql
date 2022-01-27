select /* pgwatch2_generated */
    (extract(epoch FROM now()) * 1e9)::int8 AS epoch_ns,
    *
FROM (
    SELECT
        'table'::text AS object_type,
        grantee::text AS tag_role,
        quote_ident(table_schema) || '.' || quote_ident(table_name) AS tag_object,
        privilege_type
    FROM
        information_schema.table_privileges
        /* includes also VIEW-s actually */
    WHERE
        NOT grantee = ANY (
            SELECT
                rolname
            FROM
                pg_roles
            WHERE
                rolsuper
                OR oid < 16384)
            AND NOT table_schema IN ('information_schema', 'pg_catalog')
            /*
             union all

             select
             -- quite a heavy query currently, maybe faster directly via pg_attribute + has_column_privilege?
            'column' AS object_type,
            grantee::text AS tag_role,
            quote_ident(table_schema) || '.' || quote_ident(table_name) AS tag_object,
            privilege_type
        FROM
            information_schema.column_privileges cp
        WHERE
            NOT table_schema IN ('pg_catalog', 'information_schema')
            AND NOT grantee = ANY (
                SELECT
                    rolname
                FROM
                    pg_roles
                WHERE
                    rolsuper
                    OR oid < 16384)
                AND NOT EXISTS (
                    SELECT
                        *
                    FROM
                        information_schema.table_privileges
                    WHERE
                        table_schema = cp.table_schema
                        AND table_name = cp.table_name
                        AND grantee = cp.grantee
                        AND privilege_type = cp.privilege_type) */
                UNION ALL
                SELECT
                    'function' AS object_type,
                    grantee::text AS tag_role,
                    quote_ident(routine_schema) || '.' || quote_ident(routine_name) AS tag_object,
                    privilege_type
                FROM
                    information_schema.routine_privileges
                WHERE
                    NOT routine_schema IN ('information_schema', 'pg_catalog')
                    AND NOT grantee = ANY (
                        SELECT
                            rolname
                        FROM
                            pg_roles
                        WHERE
                            rolsuper
                            OR oid < 16384)
                    UNION ALL
                    SELECT
                        'schema' AS object_type,
                        r.rolname::text AS tag_role,
                        quote_ident(n.nspname) AS tag_object,
                        p.perm AS privilege_type
                    FROM
                        pg_catalog.pg_namespace AS n
                    CROSS JOIN pg_catalog.pg_roles AS r
                    CROSS JOIN (
                        VALUES ('USAGE'),
                            ('CREATE')) AS p (perm)
                    WHERE
                        NOT n.nspname IN ('information_schema', 'pg_catalog')
                            AND n.nspname NOT LIKE 'pg_%'
                            AND NOT r.rolsuper
                            AND r.oid >= 16384
                            AND has_schema_privilege(r.oid, n.oid, p.perm)
                        UNION ALL
                        SELECT
                            'database' AS object_type,
                            r.rolname::text AS role_name,
                            quote_ident(datname) AS tag_object,
                            p.perm AS permission
                        FROM
                            pg_catalog.pg_database AS d
                        CROSS JOIN pg_catalog.pg_roles AS r
                        CROSS JOIN (
                            VALUES ('CREATE'),
                                ('CONNECT'),
                                ('TEMPORARY')) AS p (perm)
                        WHERE
                            d.datname = current_database()
                                AND NOT r.rolsuper
                                AND r.oid >= 16384
                                AND has_database_privilege(r.oid, d.oid, p.perm)
                            UNION ALL
                            SELECT
                                'superusers' AS object_type,
                                rolname::text AS role_name,
                                rolname::text AS tag_object,
                                'SUPERUSER' AS permission
                            FROM
                                pg_catalog.pg_roles
                            WHERE
                                rolsuper
                            UNION ALL
                            SELECT
                                'login_users' AS object_type,
                                rolname::text AS role_name,
                                rolname::text AS tag_object,
                                'LOGIN' AS permission
                            FROM
                                pg_catalog.pg_roles
                            WHERE
                                rolcanlogin) y;