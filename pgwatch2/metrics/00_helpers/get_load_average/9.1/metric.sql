BEGIN;

CREATE EXTENSION IF NOT EXISTS plpython3u;

CREATE OR REPLACE FUNCTION get_load_average(OUT load_1min float, OUT load_5min float, OUT load_15min float) AS
$$
from os import getloadavg
la = getloadavg()
return [la[0], la[1], la[2]]
$$ LANGUAGE plpython3u VOLATILE;

GRANT EXECUTE ON FUNCTION get_load_average() TO pgwatch2;

COMMENT ON FUNCTION get_load_average() is 'created for pgwatch2';

COMMIT;
