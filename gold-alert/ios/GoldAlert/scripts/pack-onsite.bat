@echo off
setlocal EnableExtensions
REM Build + Ad Hoc sign + publish to D:\ota-site\goldalert for Safari OTA.
REM Run from Windows; executes the WSL script.

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..") do set "IOS_WIN=%%~fI"

where wsl >nul 2>&1
if errorlevel 1 (
  echo 找不到 wsl。请在 Ubuntu WSL 里直接运行:
  echo   bash scripts/pack-onsite.sh
  exit /b 1
)

wsl -e bash -lc "cd \"$(wslpath -a '%IOS_WIN%')\" && chmod +x scripts/pack-onsite.sh scripts/gen-ota-manifest.py && ./scripts/pack-onsite.sh"
exit /b %ERRORLEVEL%
