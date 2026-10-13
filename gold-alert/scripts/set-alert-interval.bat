@echo off
setlocal EnableDelayedExpansion
chcp 65001 >nul
set "DEST=%APPDATA%\MetaQuotes\Terminal\Common\Files"
set "HERE=%~dp0"
if /I "%~1"=="install" goto install
if /I "%~1"=="auto" goto auto
if not "%~1"=="" (
  set "SEC=%~1"
  set "INTERACTIVE="
  goto validate
)

if not exist "%DEST%" mkdir "%DEST%"
echo.
echo 输入 EA 同步间隔秒数。最少 3，最多 3600。
echo 直接回车则取消。
echo 交给任务计划程序：把本文件、alert-interval-schedule.ps1 和 install-alert-interval-tasks.bat 放在同一文件夹，双击安装脚本。
echo 工作日 08:00-18:00 为 3 秒，工作日 18:00-23:00 为 10 秒，其余时间（含睡觉和周六日）为 3600 秒。
echo.
set /p SEC=秒数: 
if "%SEC%"=="" (
  echo 已取消。
  pause
  exit /b 0
)
set "INTERACTIVE=1"
goto validate

:auto
if not exist "%DEST%" mkdir "%DEST%"
set "PS1=%HERE%alert-interval-schedule.ps1"
if not exist "%PS1%" (
  echo 缺少 alert-interval-schedule.ps1，请和本脚本放在同一个文件夹。
  exit /b 1
)
set "SEC="
set "TAG="
for /f "tokens=1,2" %%a in ('powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" -Query') do (
  set "SEC=%%a"
  set "TAG=%%b"
)
if not defined SEC (
  echo 无法读取本机时间。
  exit /b 1
)
set "INTERACTIVE="
goto validate

:install
set "PS1=%HERE%alert-interval-schedule.ps1"
if not exist "%PS1%" (
  echo 缺少 alert-interval-schedule.ps1，请和本脚本放在同一个文件夹。
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" -Install -Bat "%HERE%set-alert-interval.bat"
exit /b !ERRORLEVEL!

:validate
echo %SEC%| findstr /r "^[0-9][0-9]*$" >nul
if errorlevel 1 (
  echo 请输入整数。
  if defined INTERACTIVE pause
  exit /b 1
)
:stripzero
if "!SEC:~0,1!"=="0" if not "!SEC!"=="0" (
  set "SEC=!SEC:~1!"
  goto stripzero
)
if !SEC! LSS 3 (
  echo 最少 3 秒。
  if defined INTERACTIVE pause
  exit /b 1
)
if !SEC! GTR 3600 (
  echo 最多 3600 秒。
  if defined INTERACTIVE pause
  exit /b 1
)
if not exist "%DEST%" mkdir "%DEST%"
<nul set /p "=!SEC!" > "%DEST%\gold-alert-interval.txt"
set "PERIOD="
if /I "!TAG!"=="day" set "PERIOD=工作日白天"
if /I "!TAG!"=="evening" set "PERIOD=工作日晚上"
if /I "!TAG!"=="sleep" set "PERIOD=睡觉"
if /I "!TAG!"=="weekend" set "PERIOD=周六日"
echo.
if defined PERIOD (
  echo 已设为 !SEC! 秒（!PERIOD!）。
) else (
  echo 已设为 !SEC! 秒。
)
echo EA v1.16 正在运行时，大约 1 秒后改间隔，Experts 会出现 Pull interval updated。
echo.
if defined INTERACTIVE pause
exit /b 0
