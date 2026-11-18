@echo off
rem Stop automatic history tracking.
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0watch-history.ps1" -Stop
echo.
pause
