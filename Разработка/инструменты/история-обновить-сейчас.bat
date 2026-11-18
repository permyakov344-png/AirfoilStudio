@echo off
rem Update the development archive right now (one pass) and exit.
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0watch-history.ps1" -Once -Force
echo.
pause
