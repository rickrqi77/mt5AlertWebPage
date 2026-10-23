@echo off
setlocal
chcp 65001 >nul

rem Registers two Windows Task Scheduler jobs for gold-alert interval:
rem   Mon-Fri 07:15  -> 3 seconds  (trading hours)
rem   Daily   00:00  -> 3600 seconds (night + weekend stays 3600 until Mon 07:15)
rem
rem Run this once as your normal Windows user (not necessarily admin).
rem To remove: schtasks /Delete /TN "GoldAlertIntervalDay" /F
rem            schtasks /Delete /TN "GoldAlertIntervalNight" /F

set "SI=%~dp0si.bat"
if not exist "%SI%" (
  echo Cannot find si.bat next to this script:
  echo   %SI%
  pause
  exit /b 1
)

echo Creating Task Scheduler jobs...
echo   Script: %SI%
echo.

schtasks /Create /F /TN "GoldAlertIntervalDay" /TR "\"%SI%\" 3" /SC WEEKLY /D MON,TUE,WED,THU,FRI /ST 07:15
if errorlevel 1 (
  echo Failed to create GoldAlertIntervalDay
  pause
  exit /b 1
)
echo OK: GoldAlertIntervalDay  Mon-Fri 07:15 -> 3s

schtasks /Create /F /TN "GoldAlertIntervalNight" /TR "\"%SI%\" 3600" /SC DAILY /ST 00:00
if errorlevel 1 (
  echo Failed to create GoldAlertIntervalNight
  pause
  exit /b 1
)
echo OK: GoldAlertIntervalNight  every day 00:00 -> 3600s

echo.
echo Done. Weekend stays at 3600 (set at Fri 00:00 / Sat 00:00 / Sun 00:00)
echo until Monday 07:15 switches back to 3.
echo.
echo Check:  schtasks /Query /TN GoldAlertIntervalDay /V /FO LIST
echo         schtasks /Query /TN GoldAlertIntervalNight /V /FO LIST
echo.
pause
exit /b 0
