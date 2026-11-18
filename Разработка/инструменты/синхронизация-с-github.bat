@echo off
rem ============================================================
rem  Airfoil Studio - синхронизация с GitHub
rem  Двойной щелчок: сохранить изменения, забрать чужие, отправить.
rem  Ничего не удаляет и не перезаписывает историю (без force).
rem ============================================================
chcp 65001 >nul
setlocal
cd /d "%~dp0..\.."

echo === Airfoil Studio - синхронизация с GitHub ===
echo Папка: %CD%
echo.

git rev-parse --git-dir >nul 2>&1
if errorlevel 1 (
  echo Это не git-репозиторий. Синхронизация остановлена.
  if /i not "%~1"=="auto" pause
  exit /b 1
)

git remote get-url origin >nul 2>&1
if errorlevel 1 (
  echo Не настроен remote "origin". Синхронизация остановлена.
  if /i not "%~1"=="auto" pause
  exit /b 1
)

rem --- 1. сохранить изменения ---
git add -A
git diff --cached --quiet
if errorlevel 1 (
  for /f "tokens=1 delims=,." %%t in ("%TIME%") do set "NOW=%%t"
  git commit -q -m "Автосохранение %DATE% %NOW%"
  if errorlevel 1 goto err
  echo [1/3] Коммит создан.
) else (
  echo [1/3] Новых изменений нет.
)

rem --- 2. забрать изменения с GitHub ---
git pull --rebase --autostash origin main
if errorlevel 1 goto err
echo [2/3] Изменения с GitHub получены.

rem --- 3. отправить на GitHub ---
git push origin main
if errorlevel 1 goto err
echo [3/3] Отправлено на GitHub.
echo.

echo Ветка: main
for /f "delims=" %%i in ('git log --oneline -1') do echo Последний коммит: %%i
echo Репозиторий: https://github.com/permyakov344-png/AirfoilStudio
if /i not "%~1"=="auto" pause
exit /b 0

:err
echo.
echo ОШИБКА. Ничего не потеряно: изменения остались в папке на диске.
if /i not "%~1"=="auto" pause
exit /b 1
