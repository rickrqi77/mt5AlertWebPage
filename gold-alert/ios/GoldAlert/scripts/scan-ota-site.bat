@echo off
setlocal EnableExtensions
set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..") do set "IOS_WIN=%%~fI"
wsl -e bash -lc "cd \"$(wslpath -a '%IOS_WIN%')\" && chmod +x scripts/scan-ota-site.sh scripts/gen-ota-manifest.py && ./scripts/scan-ota-site.sh"
exit /b %ERRORLEVEL%
