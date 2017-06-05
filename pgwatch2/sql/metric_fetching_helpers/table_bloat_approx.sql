CREATE EXTENSION IF NOT EXISTS pgstattuple WITH SCHEMA PUBLIC;

CREATE OR REPLACE FUNCTION public.get_table_bloat_approx(OUT approx_free_percent double precision, OUT approx_free_space double precision) AS
$$
    select
      avg(approx_free_percent)::double precision as approx_free_percent,
      sum(approx_free_space)::double precision as approx_free_space
    from
      pg_class c
      join
      pg_namespace n on n.oid = c.relnamespace
      join lateral public.pgstattuple_approx(c.oid) on true
    where
      relkind in ('r', 'm')
      and c.relpages >= 128 -- tables >1mb
      and not n.nspname like any (array[E'pg\\_%', 'information_schema'])
      having sum(approx_free_space)::double precision > 0
$$ LANGUAGE sql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.get_table_bloat_approx() TO public;
COMMENT ON FUNCTION public.get_table_bloat_approx() is 'created for pgwatch2';
