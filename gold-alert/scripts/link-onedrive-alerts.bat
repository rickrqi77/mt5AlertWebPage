@echo off
chcp 65001 >nul
setlocal
set "SRC=%OneDrive%\gold-alert"
if "%OneDrive%"=="" set "SRC=%USERPROFILE%\OneDrive\gold-alert"
set "DST=%APPDATA%\MetaQuotes\Terminal\Common\Files\gold-alert"

if not exist "%SRC%" mkdir "%SRC%"
echo Always keep this folder on this device in OneDrive: 
echo   %SRC%

if exist "%DST%" (
  echo Link already exists:
  echo   %DST%
) else (
  mklink /J "%DST%" "%SRC%"
  if errorlevel 1 (
    echo Failed to create link. Run this file as your Windows user, not as admin from another account.
    pause
    exit /b 1
  )
)

echo.
echo Done. EA will read:
echo   %DST%\alerts.txt
echo which is the same as:
echo   %SRC%\alerts.txt
echo.
pause
