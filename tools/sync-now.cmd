@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0weekly-backup.ps1"
echo.
echo Sync finished. Log: ..\AirfoilStudio_backups\weekly-backup.log
pause
