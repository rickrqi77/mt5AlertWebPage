@echo off
chcp 65001 >nul
cd /d "%~dp0"
if not exist "%~dp0set-alert-interval.bat" goto missing
if not exist "%~dp0alert-interval-schedule.ps1" goto missing
call "%~dp0set-alert-interval.bat" install
echo.
echo 可在「任务计划程序」里查看 GoldAlert Interval。
echo 触发时间：工作日 08:00、工作日 18:00、每天 23:00，以及每次登录。
echo 实际秒数按当时的钟点决定，电脑当时没开，下次登录会补上。
echo.
pause
exit /b 0

:missing
echo 请把下面三个文件放在同一个文件夹后再双击：
echo   set-alert-interval.bat
echo   alert-interval-schedule.ps1
echo   install-alert-interval-tasks.bat
echo.
pause
exit /b 1
