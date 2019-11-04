/* for cases where PL/Python is not an option. not included in preset configs */
BEGIN;

CREATE UNLOGGED TABLE IF NOT EXISTS get_load_average_copy /* remove the UNLOGGED and IF NOT EXISTS part for < v9.1 */
(
    load_1min  float,
    load_5min  float,
    load_15min float,
    proc_count text,
    last_procid int,
    created_on timestamptz not null default now()
);

CREATE OR REPLACE FUNCTION get_load_average_copy(OUT load_1min float, OUT load_5min float, OUT load_15min float) AS
$$
begin
    if random() < 0.02 then    /* clear the table on ca every 50th call not to be bigger than a couple of pages */
        truncate get_load_average_copy;
    end if;
    copy get_load_average_copy (load_1min, load_5min, load_15min, proc_count, last_procid) from '/proc/loadavg' with (format csv, delimiter ' ');
    select t.load_1min, t.load_5min, t.load_15min into load_1min, load_5min, load_15min from get_load_average_copy t order by created_on desc nulls last limit 1;
    return;
end;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_load_average_copy() TO pgwatch2;

COMMENT ON FUNCTION get_load_average_copy() is 'created for pgwatch2';

COMMIT;
