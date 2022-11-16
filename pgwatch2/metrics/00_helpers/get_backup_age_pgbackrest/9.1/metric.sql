CREATE EXTENSION IF NOT EXISTS plpython3u;
/*
  Gets age of last successful pgBackRest backup via "pgbackrest --output=json info" unix timestamp. Returns 0 retcode on success.
  Expects pgBackRest is correctly configured on monitored DB and "jq" tool is installed on the DB server.
*/
CREATE OR REPLACE FUNCTION get_backup_age_pgbackrest(OUT retcode int, OUT backup_age_seconds int, OUT message text) AS
$$
import time
import json
import subprocess

PGBACKREST_TIMEOUT = 30

def error(message, returncode=1):
  return returncode, 1000000, 'Not OK. '+message

pgbackrest_cmd=["pgbackrest", "--output=json", "info"]

try:
    p = subprocess.Popen(pgbackrest_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, encoding='utf-8')
    stdout, stderr = p.communicate(timeout=PGBACKREST_TIMEOUT)
except OSError as e:
    return error('Failed to execute pgbackrest: {}'.format(e))
except subprocess.TimeoutExpired:
    p.terminate()
    try:
        p.wait(0.5)
    except subprocess.TimeoutExpired:
        p.kill()
    return error('pgbackrest failed to respond in {} seconds'.format(PGBACKREST_TIMEOUT))

if p.returncode != 0:
    return error('Failed on "pgbackrest info" call', returncode=p.returncode)

try:
    data = json.loads(stdout)
    backup_age_seconds = int(time.time()) - data[0]['backup'][-1]['timestamp']['stop']
    return 0, backup_age_seconds, 'OK. Last backup age in seconds: {}'.format(backup_age_seconds)
except (json.JSONDecodeError, KeyError) :
    return error('Failed to parse pgbackrest output')
$$ LANGUAGE plpython3u VOLATILE;

/* contacting S3 could be laggy depending on location */
ALTER FUNCTION get_backup_age_pgbackrest() SET statement_timeout TO '30s';

GRANT EXECUTE ON FUNCTION get_backup_age_pgbackrest() TO pgwatch2;

COMMENT ON FUNCTION get_backup_age_pgbackrest() is 'created for pgwatch2';
