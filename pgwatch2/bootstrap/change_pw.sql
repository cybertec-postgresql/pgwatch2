CREATE ROLE pgwatch2 WITH LOGIN PASSWORD 'pgwatch2admin';  -- NB! change the pw for production

alter role pgwatch2 set statement_timeout to '5s';
