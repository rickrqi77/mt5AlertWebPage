@echo off
chcp 65001 >nul
cd /d "%~dp0"
if not exist "%~dp0compile-gold-alert.ps1" (
  echo 请把 compile-gold-alert.bat 和 compile-gold-alert.ps1 放在同一个文件夹后再双击。
  pause
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0compile-gold-alert.ps1"
echo.
pause
exit /b %ERRORLEVEL%
