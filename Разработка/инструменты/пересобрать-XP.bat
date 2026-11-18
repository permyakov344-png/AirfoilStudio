@echo off
rem Perebrocka XP-versii Airfoil Studio - dvojnoj shchelchok.
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build_xp.ps1" %*
echo.
pause
