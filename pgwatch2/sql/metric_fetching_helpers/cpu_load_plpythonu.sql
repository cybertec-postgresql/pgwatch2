/*

 Python function that is used to extract CPU load from machine via SQL

*/
--DROP TYPE load_average;
--DROP FUNCTION get_load_average();

BEGIN;

DROP TYPE IF EXISTS load_average CASCADE;

CREATE TYPE load_average AS ( load_1min real, load_5min real, load_15min real );

CREATE OR REPLACE FUNCTION get_load_average() RETURNS load_average AS
$$
from os import getloadavg
return getloadavg()
$$ LANGUAGE plpythonu VOLATILE SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_load_average() TO pgwatch2;

COMMENT ON FUNCTION get_load_average() is 'created for pgwatch2';

COMMIT;
