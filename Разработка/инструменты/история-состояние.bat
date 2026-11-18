@echo off
rem Show whether tracking is running, last sync time and autostart state.
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0watch-history.ps1" -Status
echo.
pause
