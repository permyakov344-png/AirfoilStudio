# Пересборка XP-версии Airfoil Studio — одной командой.
#
#   powershell -ExecutionPolicy Bypass -File build_xp.ps1
#
# Шаги: извлечь скрипт из index.html -> node --check -> собрать XP-версию ->
#       обновить запасную копию airfoil-base.js рядом с XP-файлом.
#
# Пути по умолчанию: ..\программа\index.html -> ..\программа\XP\AirfoilStudio-XP.html
# Можно указать свои:  build_xp.ps1 -Source D:\путь\index.html -Target D:\путь\XP.html

param(
  [string]$Source = "",
  [string]$Target = ""
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot

if ([string]::IsNullOrWhiteSpace($Source)) { $Source = Join-Path $here '..\программа\index.html' }
if ([string]::IsNullOrWhiteSpace($Target)) { $Target = Join-Path $here '..\программа\XP\AirfoilStudio-XP.html' }

$Source = (Resolve-Path -LiteralPath $Source).Path
$Target = [System.IO.Path]::GetFullPath($Target)

if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw 'не найден node (Node.js 18+)' }
if (-not (Get-Command python -ErrorAction SilentlyContinue)) { throw 'не найден python (Python 3)' }

$tmpJs = Join-Path $env:TEMP ('airfoil_check_' + [guid]::NewGuid().ToString('N') + '.js')

try {
  Write-Host '1/4 Извлекаю главный скрипт из index.html...'
  python (Join-Path $here 'extract_js.py') $Source $tmpJs
  if ($LASTEXITCODE -ne 0) { throw 'не удалось извлечь скрипт (изменилась разметка?)' }

  Write-Host '2/4 Проверяю синтаксис (node --check)...'
  node --check $tmpJs
  if ($LASTEXITCODE -ne 0) { throw 'СИНТАКСИЧЕСКАЯ ОШИБКА в скрипте программы — сборка отменена, XP-файл не тронут' }
  Write-Host '    синтаксис в порядке'

  Write-Host '3/4 Собираю XP-версию (Babel, цель Firefox 52)...'
  node (Join-Path $here 'build_xp.js') $Source $Target
  if ($LASTEXITCODE -ne 0) { throw 'сборка XP не удалась' }

  Write-Host '4/4 Обновляю запасную копию файл-базы для XP...'
  $base = Join-Path (Split-Path $Source) 'airfoil-base.js'
  $xpDir = Split-Path $Target
  if (Test-Path -LiteralPath $base) {
    Copy-Item -LiteralPath $base (Join-Path $xpDir 'airfoil-base.js') -Force
    Write-Host ('    скопировано: ' + $base)
  } else {
    Write-Host '    airfoil-base.js не найден — пропускаю (это не ошибка)'
  }

  Write-Host ''
  Write-Host 'ГОТОВО. Проверьте строку JSON выше: четыре значения должны быть true:'
  Write-Host '  gridGapAdded / blobTextPatched / fontPatched (+ отсутствие WARN про loader).'
  Write-Host ('XP-файл: ' + $Target)
}
finally {
  Remove-Item -LiteralPath $tmpJs -Force -ErrorAction SilentlyContinue
}
