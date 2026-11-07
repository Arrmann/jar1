# Self-heal critical JARVIS runtime files after AV quarantine / partial install.
# Seeds %ProgramData%\JARVIS\runtime-backup on healthy installs and restores from it when broken.
param(
    [Parameter(Mandatory = $true)]
    [string]$AppDir,
    [switch]$SeedOnly,
    [string]$StatusFile = ""
)

$ErrorActionPreference = "SilentlyContinue"
$AppDir = [IO.Path]::GetFullPath($AppDir)
$ProgramData = $env:ProgramData
if ([string]::IsNullOrWhiteSpace($ProgramData)) { $ProgramData = "C:\ProgramData" }
$BackupRoot = Join-Path $ProgramData "JARVIS\runtime-backup"
$ModelName = "vosk-model-small-ru-0.22"
$MinMdlBytes = 1000000

function Write-StatusLine([string]$line) {
    if (-not $StatusFile) { return }
    try {
        $utf8 = New-Object System.Text.UTF8Encoding $false
        [IO.File]::AppendAllText($StatusFile, ($line + [Environment]::NewLine), $utf8)
    } catch {}
}

function Write-Log([string]$msg) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $msg"
    try {
        $logDir = [string]$env:JARVIS_CONFIG_DIR
        if ([string]::IsNullOrWhiteSpace($logDir)) {
            if (-not (Get-Command Get-JarvisDataDir -ErrorAction SilentlyContinue)) {
                . (Join-Path $PSScriptRoot "_jarvis-data-dir.ps1")
            }
            $logDir = Get-JarvisDataDir
        }
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        Add-Content -LiteralPath (Join-Path $logDir "repair.log") -Value $line -Encoding UTF8
    } catch {}
}

function Test-AsciiPath([string]$Path) {
    return ($Path -match '^[\x00-\x7F]+$')
}

function Test-FileOk([string]$Path, [long]$MinBytes = 1) {
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    try {
        return ((Get-Item -LiteralPath $Path).Length -ge $MinBytes)
    } catch { return $false }
}

function Copy-FileForced([string]$From, [string]$To) {
    $parent = Split-Path -Parent $To
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    Copy-Item -LiteralPath $From -Destination $To -Force
}

function Ensure-DirCopy([string]$From, [string]$To) {
    if (-not (Test-Path -LiteralPath $From)) { return $false }
    New-Item -ItemType Directory -Path $To -Force | Out-Null
    cmd /c "robocopy `"$From`" `"$To`" /E /R:2 /W:1 /NFL /NDL /NJH /NJS /nc /ns /np >nul"
    return ($LASTEXITCODE -lt 8)
}

if (-not (Test-Path -LiteralPath $AppDir)) {
    Write-Log "AppDir missing: $AppDir"
    exit 1
}

if ($StatusFile) {
    try {
        $parent = Split-Path -Parent $StatusFile
        if ($parent -and -not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        $utf8 = New-Object System.Text.UTF8Encoding $false
        [IO.File]::WriteAllText($StatusFile, "", $utf8)
    } catch {}
}

# Mark-of-the-Web is cleared once during elevated Setup. Avoid recursive unblock on every launch.

$dlls = @(
    "libvosk.dll",
    "libpv_recorder.dll",
    "libgcc_s_seh-1.dll",
    "libstdc++-6.dll",
    "libwinpthread-1.dll"
)

$modelSrc = Join-Path $AppDir "resources\vosk\$ModelName"
$modelMdl = Join-Path $modelSrc "am\final.mdl"
$backupModel = Join-Path $BackupRoot $ModelName
$backupMdl = Join-Path $backupModel "am\final.mdl"
$criticalModelFiles = @(
    "$ModelName\am\final.mdl",
    "$ModelName\graph\HCLr.fst",
    "$ModelName\conf\model.conf"
)

function Test-BackupValid([string]$Root) {
    $manifest = Join-Path $Root "manifest.sha256"
    if (-not (Test-FileOk $manifest 100)) { return $false }
    try {
        $lines = Get-Content -LiteralPath $manifest -Encoding ASCII
        if ($lines.Count -lt ($dlls.Count + $criticalModelFiles.Count)) { return $false }
        foreach ($line in $lines) {
            $parts = $line.Trim() -split "\s+", 2
            if ($parts.Count -ne 2) { return $false }
            $file = Join-Path $Root $parts[1]
            if (-not (Test-Path -LiteralPath $file)) { return $false }
            if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $parts[0]) {
                return $false
            }
        }
        return $true
    } catch {
        return $false
    }
}

$installHealthy =
    (Test-FileOk (Join-Path $AppDir "jarvis-app.exe") 500000) -and
    (Test-FileOk (Join-Path $AppDir "jarvis-gui.exe") 500000) -and
    ($dlls | ForEach-Object { Test-FileOk (Join-Path $AppDir $_) 10000 } | Where-Object { -not $_ } | Measure-Object).Count -eq 0 -and
    (Test-FileOk $modelMdl $MinMdlBytes) -and
    (Test-FileOk (Join-Path $modelSrc "graph\HCLr.fst") 10000) -and
    (Test-FileOk (Join-Path $modelSrc "conf\model.conf") 10)

# 3) Only the elevated installer may seed/refresh the machine-wide backup.
# Build it beside the live cache, hash it, lock its ACL, then rename atomically.
if ($SeedOnly) {
    if (-not $installHealthy) {
        Write-Log "Refusing to seed backup from incomplete install: $AppDir"
        exit 1
    }
    $backupParent = Split-Path -Parent $BackupRoot
    $backupNew = Join-Path $backupParent ("runtime-backup.new-" + $PID)
    $backupOld = Join-Path $backupParent ("runtime-backup.old-" + $PID)
    New-Item -ItemType Directory -Path $backupParent -Force | Out-Null
    Remove-Item -LiteralPath $backupNew -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $backupOld -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $backupNew -Force | Out-Null

    foreach ($dll in $dlls) {
        $from = Join-Path $AppDir $dll
        Copy-FileForced $from (Join-Path $backupNew $dll)
    }
    if (-not (Ensure-DirCopy $modelSrc (Join-Path $backupNew $ModelName))) {
        Write-Log "Failed to copy Vosk model into temporary backup"
        Remove-Item -LiteralPath $backupNew -Recurse -Force -ErrorAction SilentlyContinue
        exit 1
    }

    $manifestLines = @()
    foreach ($relative in ($dlls + $criticalModelFiles)) {
        $file = Join-Path $backupNew $relative
        if (-not (Test-Path -LiteralPath $file)) {
            Write-Log "Backup critical file missing: $relative"
            Remove-Item -LiteralPath $backupNew -Recurse -Force -ErrorAction SilentlyContinue
            exit 1
        }
        $manifestLines += "$((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash)  $relative"
    }
    Set-Content -LiteralPath (Join-Path $backupNew "manifest.sha256") -Value $manifestLines -Encoding ASCII
    if (-not (Test-BackupValid $backupNew)) {
        Write-Log "Temporary runtime backup failed SHA256 validation"
        Remove-Item -LiteralPath $backupNew -Recurse -Force -ErrorAction SilentlyContinue
        exit 1
    }

    # Remove inherited write grants. SYSTEM/Admins own the cache; Users only read/execute.
    & "$env:SystemRoot\System32\icacls.exe" $backupNew /inheritance:r `
        /grant:r "*S-1-5-18:(OI)(CI)F" "*S-1-5-32-544:(OI)(CI)F" "*S-1-5-32-545:(OI)(CI)RX" `
        /Q | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Log "Failed to secure runtime backup ACL"
        Remove-Item -LiteralPath $backupNew -Recurse -Force -ErrorAction SilentlyContinue
        exit 1
    }
    & "$env:SystemRoot\System32\icacls.exe" (Join-Path $backupNew "*") /reset /T /C /Q | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Log "Failed to apply inherited read-only ACL to backup files"
        Remove-Item -LiteralPath $backupNew -Recurse -Force -ErrorAction SilentlyContinue
        exit 1
    }

    try {
        if (Test-Path -LiteralPath $BackupRoot) {
            Move-Item -LiteralPath $BackupRoot -Destination $backupOld -Force
        }
        Move-Item -LiteralPath $backupNew -Destination $BackupRoot -Force
        Remove-Item -LiteralPath $backupOld -Recurse -Force -ErrorAction SilentlyContinue
    } catch {
        if (-not (Test-Path -LiteralPath $BackupRoot) -and (Test-Path -LiteralPath $backupOld)) {
            Move-Item -LiteralPath $backupOld -Destination $BackupRoot -Force
        }
        Write-Log "Atomic backup replacement failed: $($_.Exception.Message)"
        exit 1
    }
    Write-Log "Seeded and verified locked runtime backup from $AppDir"
    exit 0
}

# 4) Restore missing / truncated files from ProgramData backup when the
# install folder is writable. Standard users cannot write Program Files; the
# launcher/runtime can use this backup directly in that case.
$backupValid = Test-BackupValid $BackupRoot
$restored = 0
foreach ($dll in $dlls) {
    $dst = Join-Path $AppDir $dll
    $src = Join-Path $BackupRoot $dll
    $need = -not (Test-FileOk $dst 10000)
    if ($need -and $backupValid -and (Test-FileOk $src 10000)) {
        Copy-FileForced $src $dst
        if ((Test-FileOk $dst 10000) -and
            ((Get-FileHash $src -Algorithm SHA256).Hash -eq (Get-FileHash $dst -Algorithm SHA256).Hash)) {
            $restored++
            Write-Log "Restored and verified $dll"
        }
    }
}

$modelBroken = -not (Test-FileOk $modelMdl $MinMdlBytes)
if ($modelBroken -and $backupValid -and (Test-FileOk $backupMdl $MinMdlBytes)) {
    Ensure-DirCopy $backupModel $modelSrc | Out-Null
    if (Test-FileOk $modelMdl $MinMdlBytes) {
        $restored++
        Write-Log "Restored Vosk model from ProgramData backup"
    }
}

# 5) Choose model path for the engine:
#    - healthy ASCII install model: no override (use install folder)
#    - healthy non-ASCII install: SID-scoped ProgramData mirror
#    - broken install model: verified machine backup
# Never force the backup over a healthy ASCII install.
$modelPathOut = ""
$installModelOk = (Test-FileOk $modelMdl $MinMdlBytes) -and
    (Test-FileOk (Join-Path $modelSrc "graph\HCLr.fst") 10000)
if ($installModelOk -and (Test-AsciiPath $modelSrc)) {
    $modelPathOut = ""
} elseif ($installModelOk) {
    $ensure = Join-Path $AppDir "resources\scripts\ensure-vosk-ascii.ps1"
    if (Test-Path -LiteralPath $ensure) {
        $modelPathOut = (& powershell -NoProfile -ExecutionPolicy Bypass -File $ensure -AppDir $AppDir 2>$null | Select-Object -Last 1)
        if ($modelPathOut) {
            [Environment]::SetEnvironmentVariable("JARVIS_VOSK_MODEL", "$modelPathOut", "Process")
        }
    }
} elseif ($backupValid -and (Test-FileOk $backupMdl $MinMdlBytes)) {
    $modelPathOut = $backupModel
    [Environment]::SetEnvironmentVariable("JARVIS_VOSK_MODEL", "$modelPathOut", "Process")
}

if ($modelPathOut) {
    Write-StatusLine "MODEL=$modelPathOut"
}

# Final health
$dllOk = (Test-FileOk (Join-Path $AppDir "libvosk.dll") 10000) -or $backupValid
$modelOk = $installModelOk -or
    ($backupValid -and (Test-FileOk $backupMdl $MinMdlBytes)) -or
    [bool]$modelPathOut
$finalOk = $dllOk -and $modelOk

if ($finalOk) {
    if ($backupValid) {
        Write-StatusLine "JARVIS_BACKUP_VALID=1"
    }
    Write-Log "Repair OK restored=$restored dllOk=$dllOk modelOk=$modelOk modelOut=$modelPathOut"
    exit 0
}

Write-Log "Repair incomplete restored=$restored dllOk=$dllOk modelOk=$modelOk mdl=$modelMdl"
exit 2
