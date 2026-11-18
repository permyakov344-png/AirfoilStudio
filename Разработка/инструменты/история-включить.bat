@echo off
rem Start automatic history tracking (Airfoil Studio). ASCII only: safe in any codepage.
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Minimized -File "%~dp0watch-history.ps1"
