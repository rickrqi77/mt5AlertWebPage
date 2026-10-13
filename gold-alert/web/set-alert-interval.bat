@echo off
setlocal EnableDelayedExpansion
chcp 65001 >nul
set "DEST=%APPDATA%\MetaQuotes\Terminal\Common\Files"
if not exist "%DEST%" mkdir "%DEST%"
echo.
echo 输入 EA 取提醒的间隔秒数。最少 3，最多 3600。
echo 直接回车则取消。
echo.
set /p SEC=秒数: 
if "%SEC%"=="" (
  echo 已取消。
  pause
  exit /b 0
)
echo %SEC%| findstr /r "^[0-9][0-9]*$" >nul
if errorlevel 1 (
  echo 请输入整数。
  pause
  exit /b 1
)
:stripzero
if "!SEC:~0,1!"=="0" if not "!SEC!"=="0" (
  set "SEC=!SEC:~1!"
  goto stripzero
)
if !SEC! LSS 3 (
  echo 最少 3 秒。
  pause
  exit /b 1
)
if !SEC! GTR 3600 (
  echo 最多 3600 秒。
  pause
  exit /b 1
)
<nul set /p "=!SEC!" > "%DEST%\gold-alert-interval.txt"
echo.
echo 已设为 !SEC! 秒。
echo EA v1.17 正在运行时，大约 1 分钟内改间隔，Experts 会出现 Pull interval updated。
echo.
pause
