CREATE EXTENSION IF NOT EXISTS plpython3u;

/*
  A wrapper around smartmontools to verify disk SMART health for all disk devices. 0 = SMART check PASSED.
  NB! This helper is always meant to be tested / adjusted to make sure all disk are detected etc.
  Most likely smartctl privileges must be escalated to give postgres access: sudo chmod u+s /usr/local/sbin/smartctl
*/
CREATE OR REPLACE FUNCTION get_smart_health_per_device(OUT device text, OUT retcode int) RETURNS SETOF record AS
$$

import subprocess
ret_list = []

#disk_detect_cmd='smartctl --scan | cut -d " " -f3 | grep mega' # for Lenovo ServerRAID M1210
disk_detect_cmd='lsblk -io KNAME,TYPE | grep '' disk'' | cut -d " " -f1 | sort'
p = subprocess.run(disk_detect_cmd, stdout=subprocess.PIPE, encoding='utf-8', shell=True)
if p.returncode != 0:
    return ret_list
disks = p.stdout.splitlines()

for disk in disks:
    # health_cmd = 'smartctl -d $disk -a -q silent /dev/sda' % disk    # for Lenovo ServerRAID M1210 members
    health_cmd = 'smartctl  -a -q silent /dev/%s' % disk
    p = subprocess.run(health_cmd, stdout=subprocess.PIPE, encoding='utf-8', shell=True)
    ret_list.append((disk, p.returncode))

return ret_list

$$ LANGUAGE plpython3u VOLATILE;

GRANT EXECUTE ON FUNCTION get_smart_health_per_device() TO pgwatch2;

COMMENT ON FUNCTION get_smart_health_per_device() is 'created for pgwatch2';
