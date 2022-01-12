select /* pgwatch2_generated */
  (extract(epoch from now()) * 1e9)::int8 as epoch_ns,
  quote_ident(table_schema)||'.'||quote_ident(table_name) as tag_table,
  md5((array_agg((c.*)::text order by ordinal_position))::text)
from (
         SELECT current_database()::information_schema.sql_identifier AS table_catalog, nc.nspname::information_schema.sql_identifier AS table_schema, c.relname::information_schema.sql_identifier AS table_name, a.attname::information_schema.sql_identifier AS column_name, a.attnum::information_schema.cardinal_number AS ordinal_position, pg_get_expr(ad.adbin, ad.adrelid)::information_schema.character_data AS column_default,
                CASE
                    WHEN a.attnotnull OR t.typtype = 'd'::"char" AND t.typnotnull THEN 'NO'::text
                    ELSE 'YES'::text
                    END::information_schema.yes_or_no AS is_nullable,
                CASE
                    WHEN t.typtype = 'd'::"char" THEN
                        CASE
                            WHEN bt.typelem <> 0::oid AND bt.typlen = (-1) THEN 'ARRAY'::text
                            WHEN nbt.nspname = 'pg_catalog'::name THEN format_type(t.typbasetype, NULL::integer)
                            ELSE 'USER-DEFINED'::text
                            END
                    ELSE
                        CASE
                            WHEN t.typelem <> 0::oid AND t.typlen = (-1) THEN 'ARRAY'::text
                            WHEN nt.nspname = 'pg_catalog'::name THEN format_type(a.atttypid, NULL::integer)
                            ELSE 'USER-DEFINED'::text
                            END
                    END::information_schema.character_data AS data_type, information_schema._pg_char_max_length(information_schema._pg_truetypid(a.*, t.*), information_schema._pg_truetypmod(a.*, t.*))::information_schema.cardinal_number AS character_maximum_length, information_schema._pg_char_octet_length(information_schema._pg_truetypid(a.*, t.*), information_schema._pg_truetypmod(a.*, t.*))::information_schema.cardinal_number AS character_octet_length, information_schema._pg_numeric_precision(information_schema._pg_truetypid(a.*, t.*), information_schema._pg_truetypmod(a.*, t.*))::information_schema.cardinal_number AS numeric_precision, information_schema._pg_numeric_precision_radix(information_schema._pg_truetypid(a.*, t.*), information_schema._pg_truetypmod(a.*, t.*))::information_schema.cardinal_number AS numeric_precision_radix, information_schema._pg_numeric_scale(information_schema._pg_truetypid(a.*, t.*), information_schema._pg_truetypmod(a.*, t.*))::information_schema.cardinal_number AS numeric_scale, information_schema._pg_datetime_precision(information_schema._pg_truetypid(a.*, t.*), information_schema._pg_truetypmod(a.*, t.*))::information_schema.cardinal_number AS datetime_precision, NULL::character varying::information_schema.character_data AS interval_type, NULL::character varying::information_schema.character_data AS interval_precision, NULL::character varying::information_schema.sql_identifier AS character_set_catalog, NULL::character varying::information_schema.sql_identifier AS character_set_schema, NULL::character varying::information_schema.sql_identifier AS character_set_name, NULL::character varying::information_schema.sql_identifier AS collation_catalog, NULL::character varying::information_schema.sql_identifier AS collation_schema, NULL::character varying::information_schema.sql_identifier AS collation_name,
                CASE
                    WHEN t.typtype = 'd'::"char" THEN current_database()
                    ELSE NULL::name
                    END::information_schema.sql_identifier AS domain_catalog,
                CASE
                    WHEN t.typtype = 'd'::"char" THEN nt.nspname
                    ELSE NULL::name
                    END::information_schema.sql_identifier AS domain_schema,
                CASE
                    WHEN t.typtype = 'd'::"char" THEN t.typname
                    ELSE NULL::name
                    END::information_schema.sql_identifier AS domain_name, current_database()::information_schema.sql_identifier AS udt_catalog, COALESCE(nbt.nspname, nt.nspname)::information_schema.sql_identifier AS udt_schema, COALESCE(bt.typname, t.typname)::information_schema.sql_identifier AS udt_name, NULL::character varying::information_schema.sql_identifier AS scope_catalog, NULL::character varying::information_schema.sql_identifier AS scope_schema, NULL::character varying::information_schema.sql_identifier AS scope_name, NULL::integer::information_schema.cardinal_number AS maximum_cardinality, a.attnum::information_schema.sql_identifier AS dtd_identifier, 'NO'::character varying::information_schema.yes_or_no AS is_self_referencing, 'NO'::character varying::information_schema.yes_or_no AS is_identity, NULL::character varying::information_schema.character_data AS identity_generation, NULL::character varying::information_schema.character_data AS identity_start, NULL::character varying::information_schema.character_data AS identity_increment, NULL::character varying::information_schema.character_data AS identity_maximum, NULL::character varying::information_schema.character_data AS identity_minimum, NULL::character varying::information_schema.yes_or_no AS identity_cycle, 'NEVER'::character varying::information_schema.character_data AS is_generated, NULL::character varying::information_schema.character_data AS generation_expression,
                CASE
                    WHEN c.relkind = 'r'::"char" OR c.relkind = 'v'::"char" AND (EXISTS ( SELECT 1
                                                                                          FROM pg_rewrite
                                                                                          WHERE pg_rewrite.ev_class = c.oid AND pg_rewrite.ev_type = '2'::"char" AND pg_rewrite.is_instead)) AND (EXISTS ( SELECT 1
                                                                                                                                                                                                           FROM pg_rewrite
                                                                                                                                                                                                           WHERE pg_rewrite.ev_class = c.oid AND pg_rewrite.ev_type = '4'::"char" AND pg_rewrite.is_instead)) THEN 'YES'::text
                    ELSE 'NO'::text
                    END::information_schema.yes_or_no AS is_updatable
         FROM pg_attribute a
                  LEFT JOIN pg_attrdef ad ON a.attrelid = ad.adrelid AND a.attnum = ad.adnum, pg_class c, pg_namespace nc, pg_type t
                                                                                                                               JOIN pg_namespace nt ON t.typnamespace = nt.oid
                                                                                                                               LEFT JOIN (pg_type bt
             JOIN pg_namespace nbt ON bt.typnamespace = nbt.oid) ON t.typtype = 'd'::"char" AND t.typbasetype = bt.oid
         WHERE a.attrelid = c.oid AND a.atttypid = t.oid AND nc.oid = c.relnamespace AND NOT pg_is_other_temp_schema(nc.oid) AND a.attnum > 0 AND NOT a.attisdropped AND (c.relkind = ANY (ARRAY['r'::"char", 'v'::"char"])) AND (pg_has_role(c.relowner, 'USAGE'::text) OR has_column_privilege(c.oid, a.attnum, 'SELECT, INSERT, UPDATE, REFERENCES'::text))
) c
where
  not table_schema like any (array[E'pg\\_%', 'information_schema'])
group by
  table_schema, table_name
order by
  table_schema, table_name;
