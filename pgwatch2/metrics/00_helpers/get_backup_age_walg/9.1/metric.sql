CREATE EXTENSION IF NOT EXISTS plpython3u;
/*
  Gets age of last successful WAL-G backup via "wal-g backup-list" timestamp. Returns 0 retcode on success.
  Expects .wal-g.json is correctly configured with all necessary credentials and "jq" tool is installed on the DB server.
*/
CREATE OR REPLACE FUNCTION get_backup_age_walg(OUT retcode int, OUT backup_age_seconds int, OUT message text) AS
$$
import subprocess
retcode=1
backup_age_seconds=1000000
message=''

# get latest wal-g backup timestamp
walg_last_backup_cmd="""wal-g backup-list --json | jq -r '.[0].time'"""
p = subprocess.run(walg_last_backup_cmd, stdout=subprocess.PIPE, encoding='utf-8', shell=True)
if p.returncode != 0:
    # plpy.notice("p.stdout: " + str(p.stderr) + str(p.stderr))
    return p.returncode, backup_age_seconds, 'Not OK. Failed on wal-g backup-list call'

# plpy.notice("last_tz: " + last_tz)
last_tz=p.stdout.rstrip('\n\r')

# get seconds since last backup from WAL-G timestamp in format '2020-01-22T17:50:51Z'
try:
    plan = plpy.prepare("SELECT extract(epoch from now() - $1::timestamptz)::int AS backup_age_seconds;", ["text"])
    rv = plpy.execute(plan, [last_tz])
except Exception as e:
    return retcode, backup_age_seconds, 'Not OK. Failed to convert WAL-G backup timestamp to seconds'
else:
    backup_age_seconds = rv[0]["backup_age_seconds"]
    return 0, backup_age_seconds, 'OK. Last backup age in seconds: %s' % backup_age_seconds

$$ LANGUAGE plpython3u VOLATILE;

/* contacting S3 could be laggy depending on location */
ALTER FUNCTION get_backup_age_walg() SET statement_timeout TO '30s';

GRANT EXECUTE ON FUNCTION get_backup_age_walg() TO pgwatch2;

COMMENT ON FUNCTION get_backup_age_walg() is 'created for pgwatch2';
