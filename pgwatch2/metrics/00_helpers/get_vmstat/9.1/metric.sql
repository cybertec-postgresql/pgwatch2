/*
  vmstat + some extra infos like CPU count, 1m/5m/15m load avg. and total memory
  NB! Memory and disk info returned in bytes!
*/

CREATE EXTENSION IF NOT EXISTS plpython3u; /* NB! "plpython3u" might need changing to "plpythonu" (Python 2) everywhere for older OS-es */

-- DROP FUNCTION get_vmstat(int);

CREATE OR REPLACE FUNCTION get_vmstat(
    IN delay int default 1,
    OUT r int, OUT b int, OUT swpd int8, OUT free int8, OUT buff int8, OUT cache int8, OUT si int8, OUT so int8, OUT bi int8,
    OUT bo int8, OUT "in" int, OUT cs int, OUT us int, OUT sy int, OUT id int, OUT wa int, OUT st int,
    OUT cpu_count int, OUT load_1m float4, OUT load_5m float4, OUT load_15m float4, OUT total_memory int8
)
    LANGUAGE plpython3u
AS $FUNCTION$
    from os import cpu_count, popen
    unit = 1024  # 'vmstat' default block byte size

    cpu_count = cpu_count()
    vmstat_lines = popen('vmstat {} 2'.format(delay)).readlines()
    vm = [int(x) for x in vmstat_lines[-1].split()]
    # plpy.notice(vm)
    load_1m, load_5m, load_15m = None, None, None
    with open('/proc/loadavg', 'r') as f:
        la_line = f.readline()
        if la_line:
            splits = la_line.split()
            if len(splits) == 5:
                load_1m, load_5m, load_15m = splits[0], splits[1], splits[2]

    total_memory = None
    with open('/proc/meminfo', 'r') as f:
        mi_line = f.readline()
        splits = mi_line.split()
        # plpy.notice(splits)
        if len(splits) == 3:
            total_memory = int(splits[1]) * 1024

    return vm[0], vm[1], vm[2] * unit, vm[3] * unit, vm[4] * unit, vm[5] * unit, vm[6] * unit, vm[7] * unit, vm[8] * unit, \
        vm[9] * unit, vm[10], vm[11], vm[12], vm[13], vm[14], vm[15], vm[16], cpu_count, load_1m, load_5m, load_15m, total_memory
$FUNCTION$;

GRANT EXECUTE ON FUNCTION get_vmstat(int) TO pgwatch2;
COMMENT ON FUNCTION get_vmstat(int) IS 'created for pgwatch2';
