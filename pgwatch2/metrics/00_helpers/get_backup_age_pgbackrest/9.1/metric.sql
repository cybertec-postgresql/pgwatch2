CREATE EXTENSION IF NOT EXISTS plpython3u;
/*
  Gets age of last successful pgBackRest backup via "pgbackrest --output=json info" unix timestamp. Returns 0 retcode on success.
  Expects pgBackRest is correctly configured on monitored DB and "jq" tool is installed on the DB server.
*/
CREATE OR REPLACE FUNCTION get_backup_age_pgbackrest(OUT retcode int, OUT backup_age_seconds int, OUT message text) AS
$$
import subprocess
retcode=1
backup_age_seconds=1000000
message=''

# get latest wal-g backup timestamp
walg_last_backup_cmd="""pgbackrest --output=json info | jq '.[0] | .backup[-1] | .timestamp.stop'"""
p = subprocess.run(walg_last_backup_cmd, stdout=subprocess.PIPE, encoding='utf-8', shell=True)
if p.returncode != 0:
    # plpy.notice("p.stdout: " + str(p.stderr) + str(p.stderr))
    return p.returncode, backup_age_seconds, 'Not OK. Failed on "pgbackrest info" call'

last_backup_stop_epoch=p.stdout.rstrip('\n\r')

try:
    plan = plpy.prepare("SELECT (extract(epoch from now()) - $1)::int8 AS backup_age_seconds;", ["int8"])
    rv = plpy.execute(plan, [last_backup_stop_epoch])
except Exception as e:
    return retcode, backup_age_seconds, 'Not OK. Failed to extract seconds difference via Postgres'
else:
    backup_age_seconds = rv[0]["backup_age_seconds"]
    return 0, backup_age_seconds, 'OK. Last backup age in seconds: %s' % backup_age_seconds

$$ LANGUAGE plpython3u VOLATILE;

/* contacting S3 could be laggy depending on location */
ALTER FUNCTION get_backup_age_pgbackrest() SET statement_timeout TO '30s';

GRANT EXECUTE ON FUNCTION get_backup_age_pgbackrest() TO pgwatch2;

COMMENT ON FUNCTION get_backup_age_pgbackrest() is 'created for pgwatch2';
