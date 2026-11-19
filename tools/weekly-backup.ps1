# Auto-save / sync of AirfoilStudio with GitHub.
# Runs from Windows Task Scheduler; OpenCode does not need to be open.
$ErrorActionPreference = "Stop"

$repo = Split-Path -Parent $PSScriptRoot
$logDir = Join-Path (Split-Path -Parent $repo) "AirfoilStudio_backups"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$log = Join-Path $logDir "weekly-backup.log"

if ((Test-Path $log) -and ((Get-Item $log).Length -gt 1MB)) {
    Move-Item -Force $log "$log.old"
}

function Write-Log($msg) {
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $msg" | Out-File -Append -Encoding utf8 $log
}

function Invoke-Git([string[]]$gitArgs) {
    $parts = foreach ($a in $gitArgs) {
        if ($a -match '[\s"]') { '"' + ($a -replace '"', '\"') + '"' } else { $a }
    }
    $cmdLine = "git " + ($parts -join ' ') + " 2>&1"
    $out = & cmd.exe /c $cmdLine
    $code = $LASTEXITCODE
    if ($out) { $out | Out-File -Append -Encoding utf8 $log }
    if ($code -ne 0) { throw "git $($gitArgs -join ' ') exited $code" }
    return $out
}

Set-Location $repo
$env:GIT_TERMINAL_PROMPT = "0"
$env:GCM_INTERACTIVE = "Never"
Write-Log "===== start ====="

try {
    $branch = (Invoke-Git @("rev-parse", "--abbrev-ref", "HEAD") | Select-Object -Last 1).Trim()
    if (-not $branch) { $branch = "main" }
    Write-Log "branch: $branch"

    Invoke-Git @("add", "-A") | Out-Null
    $changes = Invoke-Git @("status", "--porcelain")
    if ($changes) {
        Invoke-Git @("commit", "-m", "Auto-save $(Get-Date -Format 'yyyy-MM-dd HH:mm')") | Out-Null
        Write-Log "committed: $(@($changes).Count) file(s)"
    } else {
        Write-Log "no local changes"
    }

    # Pick up commits made on another computer, then send ours.
    Invoke-Git @("pull", "--rebase", "origin", $branch) | Out-Null
    Invoke-Git @("push", "origin", $branch) | Out-Null
    Write-Log "synced with origin/$branch"
} catch {
    Write-Log "ERROR: $_"
    if ((Test-Path (Join-Path $repo ".git\rebase-merge")) -or
        (Test-Path (Join-Path $repo ".git\rebase-apply"))) {
        & cmd.exe /c "git rebase --abort 2>&1" | Out-File -Append -Encoding utf8 $log
    }
}
