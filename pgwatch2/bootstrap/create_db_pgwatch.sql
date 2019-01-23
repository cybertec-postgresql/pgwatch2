CREATE DATABASE pgwatch2 OWNER pgwatch2;

alter role pgwatch2 in database pgwatch2 set statement_timeout to '1min';   -- just in case
