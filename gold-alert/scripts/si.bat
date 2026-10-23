@echo off
setlocal EnableDelayedExpansion
chcp 65001 >nul
set "DEST=%APPDATA%\MetaQuotes\Terminal\Common\Files"
if not exist "%DEST%" mkdir "%DEST%"

rem Usage:
rem   si.bat           interactive prompt
rem   si.bat 3         set 3 seconds (no pause; for Task Scheduler)
rem   si.bat 3600      set 3600 seconds

set "SEC=%~1"
set "QUIET=0"
if not "%SEC%"=="" set "QUIET=1"

if "%SEC%"=="" (
  echo.
  echo 输入 EA 取提醒的间隔秒数。最少 3，最多 3600。
  echo 直接回车则取消。
  echo.
  set /p SEC=秒数: 
)

if "%SEC%"=="" (
  echo 已取消。
  if "%QUIET%"=="0" pause
  exit /b 0
)

echo %SEC%| findstr /r "^[0-9][0-9]*$" >nul
if errorlevel 1 (
  echo 请输入整数。
  if "%QUIET%"=="0" pause
  exit /b 1
)

:stripzero
if "!SEC:~0,1!"=="0" if not "!SEC!"=="0" (
  set "SEC=!SEC:~1!"
  goto stripzero
)

if !SEC! LSS 3 (
  echo 最少 3 秒。
  if "%QUIET%"=="0" pause
  exit /b 1
)
if !SEC! GTR 3600 (
  echo 最多 3600 秒。
  if "%QUIET%"=="0" pause
  exit /b 1
)

<nul set /p "=!SEC!" > "%DEST%\gold-alert-interval.txt"
echo 已设为 !SEC! 秒。 [%DATE% %TIME%]
if "%QUIET%"=="0" (
  echo.
  pause
)
exit /b 0
