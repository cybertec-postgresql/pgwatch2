/*

 Python function that is used to extract CPU load from machine via SQL

*/
--DROP TYPE public.load_average;
--DROP FUNCTION public.get_load_average();

BEGIN;

DROP TYPE IF EXISTS public.load_average CASCADE;

CREATE TYPE public.load_average AS ( load_1min real, load_5min real, load_15min real );

CREATE OR REPLACE FUNCTION public.get_load_average() RETURNS public.load_average AS
$$
from os import getloadavg
return getloadavg()
$$ LANGUAGE plpythonu VOLATILE SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.get_load_average() TO public;

COMMENT ON FUNCTION public.get_load_average() is 'created for pgwatch2';

COMMIT;
