/*

 Python function for Windows that is used to extract CPU load from machine via SQL. Since
 os.getloadavg() function is unavailable for Windows, ctypes and kernel32.GetSystemTimes() 
 used
 
*/
--DROP TYPE public.load_average;
--DROP FUNCTION public.get_load_average();

BEGIN;

DROP TYPE IF EXISTS public.load_average CASCADE;
CREATE OR REPLACE FUNCTION public.cpu() RETURNS real AS
$$
	from ctypes import windll, Structure, sizeof, byref
	from ctypes.wintypes import DWORD
	import time

	class FILETIME(Structure):
	   _fields_ = [("dwLowDateTime", DWORD), ("dwHighDateTime", DWORD)]

	def GetSystemTimes():
	    __GetSystemTimes = windll.kernel32.GetSystemTimes
	    idleTime, kernelTime, userTime = FILETIME(), FILETIME(), FILETIME()
	    success = __GetSystemTimes(byref(idleTime), byref(kernelTime), byref(userTime))
	    assert success, ctypes.WinError(ctypes.GetLastError())[1]
	    return {
	        "idleTime": idleTime.dwLowDateTime,
	        "kernelTime": kernelTime.dwLowDateTime,
	        "userTime": userTime.dwLowDateTime
	       }

	FirstSystemTimes = GetSystemTimes()
	time.sleep(2)
	SecSystemTimes = GetSystemTimes()

	usr = SecSystemTimes['userTime'] - FirstSystemTimes['userTime']
	ker = SecSystemTimes['kernelTime'] - FirstSystemTimes['kernelTime']
	idl = SecSystemTimes['idleTime'] - FirstSystemTimes['idleTime']

	sys = ker + usr
	return min((sys - idl) *100 / sys, 100)
$$ LANGUAGE plpython3u;

CREATE OR REPLACE FUNCTION public.get_load_average() RETURNS public.load_average AS
$$
	CREATE TEMP TABLE IF NOT EXISTS cputimings (cpu real, ts timestamptz DEFAULT now());
	DELETE FROM cputimings WHERE ts < now() - '15 minutes' :: interval;
	WITH l1(load_1min) AS (
	  INSERT INTO cputimings(cpu) VALUES (cpu()) RETURNING *
	   ), l5(load_5min) AS (
	  SELECT avg(cpu) :: real FROM cputimings WHERE ts > now() - '5 minutes' :: interval
	   ), l15(load_15min) AS (  
	  SELECT avg(cpu) :: real FROM cputimings WHERE ts > now() - '15 minutes' :: interval
	   )
	SELECT load_1min, load_5min, load_15min  FROM l1, l5, l15;
$$ LANGUAGE sql;

GRANT EXECUTE ON FUNCTION public.get_load_average() TO public;

COMMENT ON FUNCTION public.get_load_average() is 'created for pgwatch2';

COMMIT;
