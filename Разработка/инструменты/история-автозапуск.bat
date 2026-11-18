@echo off
rem Turn on autostart of history tracking at Windows logon (a shortcut in Startup).
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0watch-history.ps1" -InstallStartup
echo.
echo To remove autostart:  powershell -File "%~dp0watch-history.ps1" -RemoveStartup
pause
