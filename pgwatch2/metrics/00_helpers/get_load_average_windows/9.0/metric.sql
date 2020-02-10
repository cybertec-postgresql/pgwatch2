/*

 Python function for Windows that is used to extract CPU load from machine via SQL. Since
 os.getloadavg() function is unavailable for Windows, ctypes and kernel32.GetSystemTimes()
 used

*/
--DROP TYPE load_average;
--DROP FUNCTION get_load_average();
--DROP FUNCTION cpu();

BEGIN;

DROP TYPE IF EXISTS load_average CASCADE;

CREATE TYPE load_average AS ( load_1min real, load_5min real, load_15min real );

CREATE OR REPLACE FUNCTION cpu() RETURNS real AS
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
	time.sleep(0.2)
	SecSystemTimes = GetSystemTimes()

	usr = SecSystemTimes['userTime'] - FirstSystemTimes['userTime']
	ker = SecSystemTimes['kernelTime'] - FirstSystemTimes['kernelTime']
	idl = SecSystemTimes['idleTime'] - FirstSystemTimes['idleTime']

	sys = ker + usr
	return min((sys - idl) *100 / sys, 100)
$$ LANGUAGE plpython3u;

CREATE OR REPLACE FUNCTION get_load_average_windows() RETURNS load_average AS
$$
	SELECT val, val, val FROM cpu() AS cpu_now(val);
$$ LANGUAGE sql;

GRANT EXECUTE ON FUNCTION get_load_average_windows() TO pgwatch2;

COMMENT ON FUNCTION get_load_average_windows() is 'created for pgwatch2';

COMMIT;
