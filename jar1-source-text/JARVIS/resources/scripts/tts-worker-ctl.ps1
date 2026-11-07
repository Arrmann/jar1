# JARVIS Silero TTS worker control: ensure | start | wait-ready | stop | status
# Background mode keeps python+model warm. Ondemand must leave zero TTS python.
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet("ensure", "start", "wait-ready", "stop", "status")]
    [string]$Action
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_jarvis-data-dir.ps1")
$hiddenHelper = Join-Path $PSScriptRoot "_jarvis-hidden-process.ps1"
if (Test-Path -LiteralPath $hiddenHelper) { . $hiddenHelper }
$pyEnvHelper = Join-Path $PSScriptRoot "_jarvis-python-env.ps1"
if (Test-Path -LiteralPath $pyEnvHelper) { . $pyEnvHelper }

$AppRoot = $null
if ($PSScriptRoot) {
    $cand = Resolve-Path (Join-Path $PSScriptRoot "..\..") -ErrorAction SilentlyContinue
    if ($cand) { $AppRoot = $cand.Path }
}
if (-not $AppRoot) { $AppRoot = (Get-Location).Path }

$pd = $env:ProgramData
if ([string]::IsNullOrWhiteSpace($pd)) { $pd = "C:\ProgramData" }
$TtsCandidates = @(
    (Join-Path $pd "JARVIS\tts"),
    (Join-Path $AppRoot "resources\tts"),
    (Join-Path $pd "JARVIS\runtime-backup\resources\tts")
)
$TtsRoot = $null
foreach ($cand in $TtsCandidates) {
    $py = Join-Path $cand "runtime\python\python.exe"
    $daemon = Join-Path $cand "tts_daemon.py"
    $m55 = Join-Path $cand "models\v5_5_ru.pt"
    $m5 = Join-Path $cand "models\v5_ru.pt"
    $modelOk = ((Test-Path $m55) -and ((Get-Item $m55).Length -gt 1000000)) -or ((Test-Path $m5) -and ((Get-Item $m5).Length -gt 1000000))
    $torchOk = $true
    if (Get-Command Test-JarvisTorchTree -ErrorAction SilentlyContinue) {
        $torchOk = Test-JarvisTorchTree (Join-Path $cand "runtime\python")
    }
    if ((Test-Path $py) -and (Test-Path $daemon) -and $modelOk -and $torchOk) {
        $TtsRoot = $cand
        break
    }
}
if (-not $TtsRoot) { $TtsRoot = $TtsCandidates[0] }
foreach ($name in @("speak.py", "tts_daemon.py")) {
    $src = Join-Path $AppRoot ("resources\tts\" + $name)
    $dst = Join-Path $TtsRoot $name
    if ((Test-Path -LiteralPath $src) -and (Test-Path -LiteralPath (Split-Path -Parent $dst))) {
        try { Copy-Item -LiteralPath $src -Destination $dst -Force } catch {}
    }
}

$PyExe = Join-Path $TtsRoot "runtime\python\python.exe"
$DaemonPy = Join-Path $TtsRoot "tts_daemon.py"
$Model = Join-Path $TtsRoot "models\v5_5_ru.pt"
if (-not (Test-Path -LiteralPath $Model)) {
    $Model = Join-Path $TtsRoot "models\v5_ru.pt"
}
$Ready = Join-Path $TtsRoot "runtime\.ready"

$DataDir = Get-JarvisDataDir
$WorkerDir = Join-Path $DataDir "tts-worker"
$PidFile = Join-Path $DataDir "tts.worker.pid"
$AliveFile = Join-Path $WorkerDir "alive"
$LoadingFile = Join-Path $WorkerDir "loading"
$ShutdownFile = Join-Path $WorkerDir "shutdown"

function Get-WorkerPid {
    if (-not (Test-Path -LiteralPath $PidFile)) { return 0 }
    $raw = (Get-Content -LiteralPath $PidFile -Raw -ErrorAction SilentlyContinue)
    if (-not $raw) { return 0 }
    $pidNum = 0
    if (-not [int]::TryParse($raw.Trim(), [ref]$pidNum)) { return 0 }
    try {
        $p = Get-Process -Id $pidNum -ErrorAction Stop
        if ($p -and ($p.ProcessName -match 'python')) { return $pidNum }
    } catch {}
    return 0
}

function Test-WorkerAlive {
    $wpid = Get-WorkerPid
    if ($wpid -le 0) { return $false }
    if (-not (Test-Path -LiteralPath $AliveFile)) { return $false }
    try {
        $ts = [int64]((Get-Content -LiteralPath $AliveFile -Raw).Trim())
        $age = [int64]([DateTime]::UtcNow - [datetime]'1970-01-01').TotalSeconds - $ts
        return ($age -ge 0 -and $age -le 12)
    } catch {
        return $false
    }
}

function Stop-Worker {
    $ErrorActionPreference = "SilentlyContinue"
    New-Item -ItemType Directory -Force -Path $WorkerDir | Out-Null
    Set-Content -LiteralPath $ShutdownFile -Value "1" -Encoding ASCII
    $wpid = Get-WorkerPid
    $deadline = (Get-Date).AddSeconds(4)
    while ((Get-Date) -lt $deadline) {
        if ($wpid -le 0 -or -not (Get-Process -Id $wpid -ErrorAction SilentlyContinue)) { break }
        Start-Sleep -Milliseconds 150
    }
    if ($wpid -gt 0) {
        Stop-Process -Id $wpid -Force -ErrorAction SilentlyContinue
    }
    # Kill ALL JARVIS TTS python leftovers (daemon + speak + any runtime python under resources\tts)
    Get-CimInstance Win32_Process -Filter "Name = 'python.exe'" -ErrorAction SilentlyContinue | ForEach-Object {
        $cmd = [string]$_.CommandLine
        if (-not $cmd) { return }
        $isJarvisTts = ($cmd -like "*tts_daemon.py*") -or ($cmd -like "*\tts\speak.py*") -or ($cmd -like "*/tts/speak.py*")
        if ($isJarvisTts) {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        }
    }
    Remove-Item -LiteralPath $PidFile, $AliveFile, $LoadingFile, $ShutdownFile -Force -ErrorAction SilentlyContinue
    $inbox = Join-Path $WorkerDir "inbox"
    if (Test-Path -LiteralPath $inbox) {
        Get-ChildItem -LiteralPath $inbox -Force -ErrorAction SilentlyContinue |
            Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
    }
}

function Test-WorkerStarting {
    if (Test-WorkerAlive) { return $false }
    if (Test-Path -LiteralPath $LoadingFile) { return $true }
    try {
        $proc = Get-CimInstance Win32_Process -Filter "Name = 'python.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -and $_.CommandLine -like "*tts_daemon.py*" } |
            Select-Object -First 1
        return ($null -ne $proc)
    } catch {
        return $false
    }
}

function Start-WorkerAsync {
    if (-not (Test-Path -LiteralPath $Ready)) { throw "Silero runtime not ready" }
    if (-not (Test-Path -LiteralPath $PyExe)) { throw "python.exe missing" }
    if (-not (Test-Path -LiteralPath $DaemonPy)) { throw "tts_daemon.py missing" }
    if (-not (Test-Path -LiteralPath $Model) -or ((Get-Item $Model).Length -lt 1000000)) {
        throw "Silero model missing (v5_5_ru.pt / v5_ru.pt)"
    }

    if (Test-WorkerAlive) { return "ready" }
    if (Test-WorkerStarting) { return "starting" }

    New-Item -ItemType Directory -Force -Path (Join-Path $WorkerDir "inbox") | Out-Null
    Remove-Item -LiteralPath $ShutdownFile -Force -ErrorAction SilentlyContinue

    $outLog = Join-Path $WorkerDir "daemon.out.log"
    $errLog = Join-Path $WorkerDir "daemon.err.log"

    Set-Content -LiteralPath $LoadingFile -Value "1" -Encoding ASCII
    $env:JARVIS_CONFIG_DIR = $DataDir
    $pyDir = Split-Path -Parent $PyExe
    if (Get-Command Apply-JarvisPythonRuntime -ErrorAction SilentlyContinue) {
        Apply-JarvisPythonRuntime $pyDir
    } else {
        $env:PYTHONHOME = $null
        $env:PYTHONPATH = $null
        $env:PYTHONNOUSERSITE = "1"
    }
    # Long-running daemon. Never pass -WindowStyle with -NoNewWindow (PS 5.1 rejects both).
    Start-Process -FilePath $PyExe `
        -ArgumentList @( ('"{0}"' -f $DaemonPy), "--model", ('"{0}"' -f $Model) ) `
        -WorkingDirectory $pyDir `
        -NoNewWindow `
        -RedirectStandardOutput $outLog `
        -RedirectStandardError $errLog | Out-Null

    return "starting"
}

function Wait-WorkerReady {
    param([int]$TimeoutSec = 180)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        if (Test-WorkerAlive) {
            Remove-Item -LiteralPath $LoadingFile -Force -ErrorAction SilentlyContinue
            return $true
        }
        if (-not (Test-WorkerStarting)) {
            Remove-Item -LiteralPath $LoadingFile -Force -ErrorAction SilentlyContinue
            $tail = ""
            $errLog = Join-Path $WorkerDir "daemon.err.log"
            if (Test-Path -LiteralPath $errLog) {
                $tail = (Get-Content -LiteralPath $errLog -Tail 12 -ErrorAction SilentlyContinue) -join "`n"
            }
            throw "TTS worker exited early. $tail"
        }
        Start-Sleep -Milliseconds 400
    }
    Remove-Item -LiteralPath $LoadingFile -Force -ErrorAction SilentlyContinue
    throw "TTS worker failed to become ready within ${TimeoutSec}s"
}

function Start-Worker {
    $state = Start-WorkerAsync
    if ($state -eq "ready") { return }
    Wait-WorkerReady -TimeoutSec 180 | Out-Null
}

try {
    switch ($Action) {
        "status" {
            $alive = Test-WorkerAlive
            $starting = (-not $alive) -and (Test-WorkerStarting)
            $wpid = Get-WorkerPid
            if ($starting -and $wpid -le 0) {
                try {
                    $p = Get-CimInstance Win32_Process -Filter "Name = 'python.exe'" -ErrorAction SilentlyContinue |
                        Where-Object { $_.CommandLine -and $_.CommandLine -like "*tts_daemon.py*" } |
                        Select-Object -First 1
                    if ($p) { $wpid = [int]$p.ProcessId }
                } catch {}
            }
            Write-Output ("alive={0};starting={1};pid={2}" -f $alive, $starting, $wpid)
            if ($alive) { exit 0 } else { exit 1 }
        }
        "start" {
            $state = Start-WorkerAsync
            Write-Output $state
            exit 0
        }
        "wait-ready" {
            Wait-WorkerReady -TimeoutSec 180 | Out-Null
            Write-Output "ready"
            exit 0
        }
        "stop" {
            Stop-Worker
            Write-Output "stopped"
            exit 0
        }
        "ensure" {
            if (Test-WorkerAlive) {
                Write-Output "ready"
                exit 0
            }
            [void](Start-WorkerAsync)
            Wait-WorkerReady -TimeoutSec 180 | Out-Null
            Write-Output "started"
            exit 0
        }
    }
} catch {
    Write-Output ("ERROR: " + $_.Exception.Message)
    exit 1
}
