/* SHOW POOL_NODES expected to be 1st "command" */
SHOW POOL_NODES;
/* special handling in code - when below SHOW POOL_PROCESSES line is defined pgpool_stats will have additional summary columns:
 processes_total, processes_active */
SHOW POOL_PROCESSES;
