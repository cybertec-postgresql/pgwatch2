/*

 Python function that is used to extract CPU load from machine via SQL

*/
--DROP FUNCTION get_load_average();

BEGIN;

CREATE EXTENSION IF NOT EXISTS plpythonu; /* NB! "plpythonu" might need changing to "plpython3u" everywhere for new OS-es */

CREATE OR REPLACE FUNCTION public.get_load_average(OUT load_1min float, OUT load_5min float, OUT load_15min float) AS
$$
from os import getloadavg
la = getloadavg()
return [la[0], la[1], la[2]]
$$ LANGUAGE plpythonu VOLATILE SECURITY DEFINER;

REVOKE EXECUTE ON FUNCTION public.get_load_average() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_load_average() TO pgwatch2;

COMMENT ON FUNCTION public.get_load_average() is 'created for pgwatch2';

COMMIT;
