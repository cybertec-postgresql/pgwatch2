# Non-SQL metric gathering

On rare occasions due to various reasons (security mostly) it's not possible to gather the Postgres or OS metrics directly
over SQL, even via some wrapper functions. Here (in sub-folders) are some example use cases for such workarounds.

## Hard disk S.M.A.R.T. monitoring data "pushing"

Although reading of SMART metric could theoretically be done via SQL it would need privilege escalation. So instead here
we would have a Cronjob from a privileged user that pushes the SMART status to the pgwatch2 metrics DB regularly.

Prerequisites: `apt install smartmontools`
 
## Importing of *vmstat* log files with OS metrics into the pgwatch2 metrics DB 

For cases where we don't have superuser access to create Python wrappers or it's some ancient or locked down OS where
there's no Python or the PL/Python extension available, we can separately collect the *vmstat* data and later feed it
into pgwatch2 metric DB to be able to correlate PG internal metrics with what's happening on the OS level. There's also
a Grafana dashboard provided in a *json* definition. 
     

Prerequisites - a *vmstat* log file with timestamps enabled: `vmstat -t 60 &> vmstat.log`

Command to load a vmstat log file:

```
./vmstat-importer.py -f vmstat.log --pgwatch2-dbname app1_db -d pgwatch2_metric -U pgwatch2
```

Command to *stream* vmstat data to pgwatch2 metrics DB as it trickles in:

```
vmstat -t 60 | ./vmstat-importer.py -f-log --pgwatch2-dbname app1_db -d pgwatch2_metric -U pgwatch2
```
