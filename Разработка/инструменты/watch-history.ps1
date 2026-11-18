# Автоматическая история разработки Airfoil Studio.
#
# Следит за папкой программы и сам поддерживает папку "Разработка" в актуальном
# состоянии: копирует изменённые файлы, пересобирает XP-версию, делает снимки,
# дописывает журнал изменений и (не чаще раза в 30 минут) обновляет zip-архив.
#
# Режимы:
#   -Once             один проход и выход (обновить историю сейчас)
#   -InstallStartup   прописать автозапуск слежения при входе в Windows
#   -RemoveStartup    убрать автозапуск
#   -Status           показать, работает ли слежение и когда была синхронизация
#   -Stop             остановить запущенное слежение
#   (без ключей)      работать постоянно в фоне
#
# Прочие ключи:
#   -NoBuild          не пересобирать XP-версию
#   -NoZip            не обновлять zip-архив
#   -Force            записать в журнал запись, даже если файлы не изменились
#   -DelaySec 20      сколько секунд ждать после последнего изменения
#   -KeepSnapshots 40 сколько снимков хранить
#   -ZipCooldownMin 30 как часто обновлять zip

[CmdletBinding()]
param(
  [switch]$Once,
  [switch]$InstallStartup,
  [switch]$RemoveStartup,
  [switch]$Status,
  [switch]$Stop,
  [switch]$NoBuild,
  [switch]$NoZip,
  [switch]$Force,
  [int]$DelaySec = 20,
  [int]$KeepSnapshots = 40,
  [int]$ZipCooldownMin = 30
)

$ErrorActionPreference = 'Stop'

# ---------- пути ----------
$here = $PSScriptRoot
$dev = Split-Path $here -Parent                    # ...\AirfoilStudio\Разработка
$proj = Split-Path $dev -Parent                    # ...\AirfoilStudio

$progDst = Join-Path $dev 'программа'
$histDir = Join-Path $dev 'история'
$snapDir = Join-Path $histDir 'снимки'
$journal = Join-Path $histDir 'ЖУРНАЛ-ИЗМЕНЕНИЙ.md'
$stateF = Join-Path $histDir 'СОСТОЯНИЕ.txt'
$logF = Join-Path $histDir 'журнал-слежения.log'
$zipPath = Join-Path $proj 'AirfoilStudio-Разработка.zip'
$stampF = Join-Path $histDir '.zip-stamp'
$ps1Path = Join-Path $here 'watch-history.ps1'

foreach ($d in @($progDst, (Join-Path $progDst 'XP'), $histDir, $snapDir)) {
  New-Item -ItemType Directory -Force -Path $d | Out-Null
}

# Источник правды: папка, где реально лежит программа. Если архив перенесли
# отдельно (рядом нет index.html) — работаем с копией внутри "программа".
$srcProj = if (Test-Path -LiteralPath (Join-Path $proj 'index.html')) { $proj } else { $progDst }
$sameFolder = ($srcProj -eq $progDst)
$devLeaf = Split-Path $dev -Leaf

# ---------- вспомогательное ----------
function Write-Log([string]$msg) {
  $line = (Get-Date -Format 'dd.MM.yyyy HH:mm:ss') + '  ' + $msg
  Add-Content -LiteralPath $logF -Value $line -Encoding UTF8
  if (Test-Path -LiteralPath $logF) {
    $sz = (Get-Item -LiteralPath $logF).Length
    if ($sz -gt 512KB) {
      Move-Item -LiteralPath $logF -Destination ($logF + '.old') -Force
    }
  }
}

function Get-HashOf([string]$p) {
  if (Test-Path -LiteralPath $p) { (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash } else { '' }
}

function Copy-Retry([string]$from, [string]$to) {
  for ($i = 0; $i -lt 10; $i++) {
    try {
      Copy-Item -LiteralPath $from -Destination $to -Force -ErrorAction Stop
      return $true
    } catch {
      Start-Sleep -Milliseconds 300
    }
  }
  return $false
}

function Get-Lines([string]$p) {
  if (-not (Test-Path -LiteralPath $p)) { return 0 }
  $t = Get-Content -LiteralPath $p -Raw
  if ($null -eq $t) { return 0 }
  return ($t -split "`n").Count
}

function Format-Size([long]$b) {
  if ($b -ge 1MB) { return ('{0:N1} МБ' -f ($b / 1MB)) }
  if ($b -ge 1KB) { return ('{0:N0} КБ' -f ($b / 1KB)) }
  return "$b Б"
}

function Add-Journal([string[]]$lines) {
  if (-not (Test-Path -LiteralPath $journal)) {
    $head = @(
      '# Журнал изменений Airfoil Studio',
      '',
      'Файл заполняется **автоматически**: `инструменты\watch-history.ps1` следит за папкой',
      'программы и дописывает сюда каждое изменение. Руками править можно — скрипт только',
      'дописывает новые записи снизу.',
      '',
      'Как это работает и как включить/выключить — `ЧИТАТЬ_ПЕРВЫМ.md`, раздел «История обновляется сама».',
      ''
    )
    Set-Content -LiteralPath $journal -Value $head -Encoding UTF8
  }
  Add-Content -LiteralPath $journal -Value $lines -Encoding UTF8
}

# ---------- пересборка XP ----------
function Rebuild-XP {
  $srcHtml = Join-Path $progDst 'index.html'
  $dstHtml = Join-Path $progDst 'XP\AirfoilStudio-XP.html'
  $tmp = Join-Path $env:TEMP ('af_watch_' + [guid]::NewGuid().ToString('N') + '.js')
  try {
    $out = & python (Join-Path $here 'extract_js.py') $srcHtml $tmp 2>&1
    if ($LASTEXITCODE -ne 0) { return @{ ok = $false; msg = "не удалось извлечь скрипт: $out" } }

    $out = & node @('--check', $tmp) 2>&1
    if ($LASTEXITCODE -ne 0) { return @{ ok = $false; msg = "синтаксическая ошибка в index.html — XP не пересобиралась" } }

    $out = & node (Join-Path $here 'build_xp.js') $srcHtml $dstHtml 2>&1
    if ($LASTEXITCODE -ne 0) { return @{ ok = $false; msg = "сборка XP не удалась: $out" } }

    $json = ($out | Select-Object -Last 1)
    $base = Join-Path $progDst 'airfoil-base.js'
    if (Test-Path -LiteralPath $base) {
      Copy-Item -LiteralPath $base -Destination (Join-Path $progDst 'XP\airfoil-base.js') -Force
    }

    # держим XP-версию в самой папке программы тоже свежей
    if (-not $sameFolder) {
      $xpSrc = Join-Path $proj 'XP'
      if (Test-Path -LiteralPath $xpSrc) {
        Copy-Retry $dstHtml (Join-Path $xpSrc 'AirfoilStudio-XP.html') | Out-Null
        if (Test-Path -LiteralPath $base) {
          Copy-Retry $base (Join-Path $xpSrc 'airfoil-base.js') | Out-Null
        }
      }
    }
    return @{ ok = $true; msg = $json }
  } catch {
    return @{ ok = $false; msg = $_.Exception.Message }
  } finally {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
  }
}

# ---------- основная синхронизация ----------
$pairs = @(
  @{ rel = 'index.html';                          sub = '' },
  @{ rel = 'airfoil-base.js';                     sub = '' },
  @{ rel = 'XP\AirfoilStudio-XP.html';            sub = 'XP' },
  @{ rel = 'XP\airfoil-base.js';                  sub = 'XP' },
  @{ rel = 'XP\Как запустить на Windows XP.txt';  sub = 'XP' }
)

function Sync-History([string]$reason) {
  $changed = New-Object System.Collections.Generic.List[object]
  $notes = New-Object System.Collections.Generic.List[string]
  $when = Get-Date -Format 'dd.MM.yyyy HH:mm'

  foreach ($p in $pairs) {
    $src = Join-Path $srcProj $p.rel
    $dst = Join-Path $progDst $p.rel
    if (-not (Test-Path -LiteralPath $src)) { continue }
    if ($src -eq $dst) { continue }

    if ((Get-HashOf $src) -eq (Get-HashOf $dst)) { continue }

    $oldSize = 0; $oldLines = 0
    if (Test-Path -LiteralPath $dst) {
      $oldSize = (Get-Item -LiteralPath $dst).Length
      if ($p.rel -eq 'index.html') { $oldLines = Get-Lines $dst }
    }
    $newSize = (Get-Item -LiteralPath $src).Length

    if (-not (Copy-Retry $src $dst)) {
      Write-Log ("НЕ удалось скопировать " + $p.rel + " (файл занят?)")
      $notes.Add('- ! не удалось скопировать `' + $p.rel + '` — файл занят, попробую позже')
      continue
    }
    $newLines = 0
    if ($p.rel -eq 'index.html') { $newLines = Get-Lines $dst }
    $changed.Add([pscustomobject]@{ rel = $p.rel; old = $oldSize; new = $newSize; oldLines = $oldLines; newLines = $newLines })
    Write-Log ("скопировано: " + $p.rel + " (" + $newSize + " Б)")
  }

  $indexChanged = $false
  foreach ($c in $changed) { if ($c.rel -eq 'index.html') { $indexChanged = $true } }

  # снимок исходника — точка, к которой можно вернуться
  $snapName = ''
  $xpNote = ''
  if ($indexChanged) {
    $snapName = 'index-' + (Get-Date -Format 'yyyy-MM-dd_HHmmss') + '.html'
    Copy-Item -LiteralPath (Join-Path $progDst 'index.html') -Destination (Join-Path $snapDir $snapName) -Force
    $all = Get-ChildItem -LiteralPath $snapDir -Filter 'index-*.html' | Sort-Object Name
    if ($all.Count -gt $KeepSnapshots) {
      $all | Select-Object -First ($all.Count - $KeepSnapshots) | ForEach-Object {
        Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
      }
    }
    Write-Log ("снимок: " + $snapName)
  }

  # XP-версия пересобирается сама, если менялся index.html
  if ($indexChanged -and -not $NoBuild) {
    $r = Rebuild-XP
    if ($r.ok) {
      $xpNote = 'XP-версия пересобрана автоматически'
      Write-Log ("XP: " + $r.msg)
    } else {
      $xpNote = 'XP-версия НЕ пересобрана: ' + $r.msg
      Write-Log ("ОШИБКА XP: " + $r.msg)
    }
  }

  # zip для переноса (не чаще, чем раз в $ZipCooldownMin минут)
  $zipNote = ''
  if (-not $NoZip -and $changed.Count -gt 0) {
    $lastZip = [datetime]'2000-01-01'
    if (Test-Path -LiteralPath $stampF) {
      try { $lastZip = [datetime]::Parse((Get-Content -LiteralPath $stampF -Raw).Trim()) } catch { }
    }
    if (((Get-Date) - $lastZip).TotalMinutes -ge $ZipCooldownMin) {
      try {
        Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
        Compress-Archive -Path (Join-Path $dev '*') -DestinationPath $zipPath -CompressionLevel Optimal -Force
        Set-Content -LiteralPath $stampF -Value (Get-Date -Format 'o') -Encoding ASCII
        $zipNote = 'zip для переноса обновлён: ' + (Split-Path $zipPath -Leaf)
        Write-Log $zipNote
      } catch {
        Write-Log ('zip не обновился: ' + $_.Exception.Message)
        $zipNote = 'zip НЕ обновился: ' + $_.Exception.Message
      }
    }
  }

  # журнал
  if ($changed.Count -gt 0 -or $Force) {
    $md = New-Object System.Collections.Generic.List[string]
    $md.Add('')
    $md.Add('## ' + $when)
    $md.Add('')
    if ($reason) { $md.Add('*Что произошло:* ' + $reason) }
    if ($changed.Count -eq 0) {
      $md.Add('- изменений в файлах нет (проверка по запросу)')
    }
    foreach ($c in $changed) {
      $line = '- `' + $c.rel + '` — ' + (Format-Size $c.new) + ' (было ' + (Format-Size $c.old) + ')'
      if ($c.rel -eq 'index.html') {
        $dl = $c.newLines - $c.oldLines
        $sign = if ($dl -ge 0) { '+' } else { '' }
        $line += ', строк ' + $c.newLines + ' (' + $sign + $dl + ')'
      }
      $md.Add($line)
    }
    if ($snapName) { $md.Add('- снимок: `история\снимки\' + $snapName + '`') }
    if ($xpNote) { $md.Add('- ' + $xpNote) }
    if ($zipNote) { $md.Add('- ' + $zipNote) }
    foreach ($n in $notes) { $md.Add($n) }
    $md.Add('')
    Add-Journal $md.ToArray()
  }

  # состояние — чтобы всегда было видно, когда архив обновлялся
  $idx = Join-Path $progDst 'index.html'
  $xpH = Join-Path $progDst 'XP\AirfoilStudio-XP.html'
  $snaps = @(Get-ChildItem -LiteralPath $snapDir -Filter 'index-*.html' -ErrorAction SilentlyContinue)
  $st = @(
    'Airfoil Studio — состояние архива разработки',
    ('Обновлено: ' + $when),
    ('Источник: ' + $srcProj),
    ('Файлов в папке "программа": ' + @(Get-ChildItem -LiteralPath $progDst -Recurse -File).Count),
    ('index.html: ' + (Format-Size (Get-Item -LiteralPath $idx).Length) + ', SHA256 ' + (Get-HashOf $idx)),
    ('XP-версия: ' + (Format-Size (Get-Item -LiteralPath $xpH).Length) + ', SHA256 ' + (Get-HashOf $xpH)),
    ('Снимков: ' + $snaps.Count),
    ('Zip: ' + $(if (Test-Path -LiteralPath $zipPath) { $zipPath + ' (' + (Format-Size (Get-Item -LiteralPath $zipPath).Length) + ')' } else { 'ещё не создавался' }))
  )
  Set-Content -LiteralPath $stateF -Value $st -Encoding UTF8

  if ($changed.Count -gt 0 -or $Force) {
    Write-Host ('  обновлено: ' + $when + ' — изменённых файлов: ' + $changed.Count)
    foreach ($c in $changed) { Write-Host ('    ' + $c.rel + ' — ' + (Format-Size $c.new)) }
    if ($snapName) { Write-Host ('    снимок: ' + $snapName) }
    if ($xpNote) { Write-Host ('    ' + $xpNote) }
    if ($zipNote) { Write-Host ('    ' + $zipNote) }
  }

  return $changed.Count
}

# ---------- служебные режимы ----------
function Get-Watchers {
  # только настоящий «часовой»: запущен через -File, а не через -Command
  # (иначе в список попадает оболочка, из которой вызвали этот скрипт)
  Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object {
      $_.CommandLine -and
      $_.CommandLine -like '*-File*watch-history.ps1*' -and
      $_.CommandLine -notlike '*-Command*'
    }
}

if ($Stop) {
  $mine = Get-Watchers | Where-Object { $_.ProcessId -ne $PID }
  if (-not $mine) { Write-Host 'Слежение не запущено.'; exit 0 }
  foreach ($p in $mine) {
    Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
    Write-Host ('Остановлено: процесс ' + $p.ProcessId)
  }
  exit 0
}

if ($Status) {
  $run = Get-Watchers | Where-Object { $_.ProcessId -ne $PID }
  if ($run) {
    Write-Host 'Слежение РАБОТАЕТ:'
    foreach ($p in $run) { Write-Host ('  процесс ' + $p.ProcessId + ', запущен ' + $p.CreationDate) }
  } else {
    Write-Host 'Слежение НЕ запущено.'
  }
  $startup = Join-Path ([Environment]::GetFolderPath('Startup')) 'Airfoil Studio - history.lnk'
  if (Test-Path -LiteralPath $startup) { Write-Host ('Автозапуск включён: ' + $startup) } else { Write-Host 'Автозапуск выключен.' }
  if (Test-Path -LiteralPath $stateF) {
    Write-Host ''
    Get-Content -LiteralPath $stateF
  }
  exit 0
}

if ($InstallStartup -or $RemoveStartup) {
  $startupDir = [Environment]::GetFolderPath('Startup')
  $lnk = Join-Path $startupDir 'Airfoil Studio - history.lnk'
  if ($RemoveStartup) {
    if (Test-Path -LiteralPath $lnk) { Remove-Item -LiteralPath $lnk -Force; Write-Host 'Автозапуск выключен.' }
    else { Write-Host 'Автозапуска и не было.' }
    exit 0
  }
  $wsh = New-Object -ComObject WScript.Shell
  $s = $wsh.CreateShortcut($lnk)
  $s.TargetPath = 'powershell.exe'
  $s.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $ps1Path + '"'
  $s.WorkingDirectory = $here
  $s.WindowStyle = 7
  $s.Description = 'Airfoil Studio: автоматическая история разработки'
  $s.Save()
  Write-Host ('Автозапуск включён: ' + $lnk)
  exit 0
}

if ($Once) {
  Write-Log ('разовая синхронизация (источник: ' + $srcProj + ')')
  $n = Sync-History 'обновление по команде'
  if ($n -eq 0) { Write-Host 'Изменений нет — архив уже актуален.' }
  exit 0
}

# ---------- постоянное слежение ----------
$mutex = New-Object System.Threading.Mutex($false, 'Local\AirfoilStudioHistoryWatcher')
if (-not $mutex.WaitOne(0)) {
  Write-Host 'Слежение уже запущено — второй экземпляр не нужен.'
  exit 0
}

try {
  Write-Log ('--- слежение запущено, папка: ' + $srcProj)

  # то, что пропустили, пока слежение было выключено
  Sync-History 'запуск слежения'

  $watcher = New-Object System.IO.FileSystemWatcher
  $watcher.Path = $srcProj
  $watcher.IncludeSubdirectories = $true
  $watcher.NotifyFilter = [System.IO.NotifyFilters]::LastWrite -bor
                          [System.IO.NotifyFilters]::FileName -bor
                          [System.IO.NotifyFilters]::Size -bor
                          [System.IO.NotifyFilters]::CreationTime
  $watcher.EnableRaisingEvents = $true

  $interesting = '^(index\.html|airfoil-base\.js|AirfoilStudio-XP\.html|Как запустить на Windows XP\.txt)$'
  $pending = $false
  $lastChange = Get-Date
  $seen = New-Object System.Collections.Generic.List[string]

  while ($true) {
    $res = $watcher.WaitForChanged([System.IO.WatcherChangeTypes]::All, 1000)
    if (-not $res.TimedOut -and $res.Name) {
      # свои же записи внутри "Разработка" не считаем изменением программы
      $isOwn = $res.Name -like ($devLeaf + '\*')
      $leaf = Split-Path $res.Name -Leaf
      if (-not $isOwn -and $leaf -match $interesting) {
        $pending = $true
        $lastChange = Get-Date
        if (-not $seen.Contains($res.Name)) { $seen.Add($res.Name) }
      }
    }
    if ($pending -and ((Get-Date) - $lastChange).TotalSeconds -ge $DelaySec) {
      $pending = $false
      $list = ($seen -join ', ')
      $seen.Clear()
      try {
        Sync-History ('изменены файлы: ' + $list)
      } catch {
        Write-Log ('ОШИБКА синхронизации: ' + $_.Exception.Message)
      }
      $lastChange = Get-Date
    }
  }
} finally {
  if ($watcher) { $watcher.Dispose() }
  $mutex.ReleaseMutex()
  Write-Log '--- слежение остановлено'
}
