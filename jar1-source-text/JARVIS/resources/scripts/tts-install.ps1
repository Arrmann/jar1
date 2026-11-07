# Install / repair local Silero TTS (from Settings).
# Progress -> <JARVIS data dir>\tts-install.json
# ASCII-only for Windows PowerShell 5.1.
param(
    [switch]$StatusOnly
)

$ErrorActionPreference = "Continue"
. (Join-Path $PSScriptRoot "_jarvis-data-dir.ps1")
$pyEnvHelper = Join-Path $PSScriptRoot "_jarvis-python-env.ps1"
if (Test-Path -LiteralPath $pyEnvHelper) { . $pyEnvHelper }

$AppRoot = $null
if ($PSScriptRoot) {
    $cand = Resolve-Path (Join-Path $PSScriptRoot "..\..") -ErrorAction SilentlyContinue
    if ($cand) { $AppRoot = $cand.Path }
}
if (-not $AppRoot) { $AppRoot = (Get-Location).Path }

$DataDir = Get-JarvisDataDir
New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
$StatusFile = Join-Path $DataDir "tts-install.json"
$LogFile = Join-Path $DataDir "tts-install.log"
$LockFile = Join-Path $DataDir "tts-install.lock"
$WrapperPs1 = Join-Path $DataDir "tts-fetch-run.ps1"

$FetchScript = Join-Path $AppRoot "resources\scripts\fetch-silero-tts.ps1"
if (-not (Test-Path -LiteralPath $FetchScript)) {
    $FetchScript = Join-Path $AppRoot "tools\fetch-silero-tts.ps1"
}

function Write-Status([string]$State, [string]$Message, [int]$Percent = 0) {
    if ($Percent -lt 0) { $Percent = 0 }
    if ($Percent -gt 100) { $Percent = 100 }
    $obj = @{
        state = $State
        message = $Message
        percent = $Percent
        updated_at = (Get-Date).ToString("o")
        log = $LogFile
    } | ConvertTo-Json -Compress
    [IO.File]::WriteAllText($StatusFile, $obj, [Text.UTF8Encoding]::new($false))
}

function Test-AsciiPath([string]$Path) {
    return ($Path -match '^[\x00-\x7F]+$')
}

function Get-TtsReady {
    $pd = $env:ProgramData
    if ([string]::IsNullOrWhiteSpace($pd)) { $pd = "C:\ProgramData" }
    $roots = @(
        (Join-Path $pd "JARVIS\tts"),
        (Join-Path $AppRoot "resources\tts")
    )
    foreach ($tts in $roots) {
        if (-not (Test-AsciiPath $tts)) { continue }
        $rt = Join-Path $tts "runtime"
        $ttsItem = Get-Item -LiteralPath $tts -Force -ErrorAction SilentlyContinue
        $rtItem = Get-Item -LiteralPath $rt -Force -ErrorAction SilentlyContinue
        if ($ttsItem -and ($ttsItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) { continue }
        if ($rtItem -and ($rtItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) { continue }
        $py = Join-Path $tts "runtime\python\python.exe"
        $speak = Join-Path $tts "speak.py"
        $m55 = Join-Path $tts "models\v5_5_ru.pt"
        $m5 = Join-Path $tts "models\v5_ru.pt"
        $modelOk = ((Test-Path $m55) -and ((Get-Item $m55).Length -gt 1000000)) -or ((Test-Path $m5) -and ((Get-Item $m5).Length -gt 1000000))
        $pyDir = Join-Path $tts "runtime\python"
        $torchOk = $false
        if (Get-Command Test-JarvisTorchTree -ErrorAction SilentlyContinue) {
            $torchOk = Test-JarvisTorchTree $pyDir
        } else {
            $torch = Join-Path $pyDir "Lib\site-packages\torch\__init__.py"
            $cpu = Join-Path $pyDir "Lib\site-packages\torch\lib\c10.dll"
            $torchOk = (Test-Path $torch) -and (Test-Path $cpu)
        }
        if ((Test-Path $py) -and (Test-Path $speak) -and $modelOk -and $torchOk) { return $true }
    }
    return $false
}

function Map-StepPercent([string]$line) {
    $l = $line.ToLowerInvariant()
    if ($l -match 'step:copy-bundled' -or $l -match 'copying bundled') { return 45 }
    if ($l -match 'ok silero ready \(copied') { return 96 }
    if ($l -match 'step:python') { return 12 }
    if ($l -match 'step:pip') { return 22 }
    if ($l -match 'step:torch' -or $l -match 'torch via') { return 35 }
    if ($l -match 'step:numpy') { return 62 }
    if ($l -match 'step:model-fallback') { return 78 }
    if ($l -match 'step:model') { return 70 }
    if ($l -match 'step:smoke') { return 90 }
    if ($l -match 'ok silero ready') { return 98 }
    return -1
}

function Test-BundledSilero {
    $tts = Join-Path $AppRoot "resources\tts"
    $py = Join-Path $tts "runtime\python\python.exe"
    $speak = Join-Path $tts "speak.py"
    $m55 = Join-Path $tts "models\v5_5_ru.pt"
    $m5 = Join-Path $tts "models\v5_ru.pt"
    $modelOk = ((Test-Path $m55) -and ((Get-Item $m55).Length -gt 1000000)) -or ((Test-Path $m5) -and ((Get-Item $m5).Length -gt 1000000))
    $init = Join-Path $tts "runtime\python\Lib\site-packages\torch\__init__.py"
    $cpu = Join-Path $tts "runtime\python\Lib\site-packages\torch\lib\c10.dll"
    return ((Test-Path $py) -and (Test-Path $speak) -and $modelOk -and (Test-Path $init) -and (Test-Path $cpu))
}

function Humanize-Error([string]$raw) {
    $t = ($raw -replace '\s+', ' ').Trim()
    if ($t.Length -gt 320) { $t = $t.Substring(0, 320) + "..." }
    if ($t -match '(?i)robocopy|copy-bundled|copying bundled') {
        return "Не скопировалась встроенная озвучка. Закрой JARVIS и нажми «Повторить». Лог: tts-install.log"
    }
    if ($t -match '(?i)torch|pytorch') {
        return "Не скачался PyTorch (часто режут в РФ). Включи VPN и нажми «Повторить». Подробности: tts-install.log"
    }
    if ($t -match '(?i)python\.org|embed-amd64|python\.exe missing|All mirrors failed.*python') {
        return "Не скачался Python. Проверь интернет/VPN и повтори. Лог: tts-install.log"
    }
    if ($t -match '(?i)silero|model missing|models\.silero') {
        return "Не скачалась модель Silero. VPN и «Повторить». Лог: tts-install.log"
    }
    if ($t -match '(?i)get-pip|pip install') {
        return "Ошибка pip. VPN и «Повторить». Лог: tts-install.log"
    }
    if ([string]::IsNullOrWhiteSpace($t)) {
        return "Установка Silero сорвалась. VPN и «Повторить». Лог: tts-install.log"
    }
    return $t
}

if ($StatusOnly) {
    if (Get-TtsReady) {
        Write-Status "ready" "Local Silero is installed." 100
    } elseif (Test-Path $LockFile) {
        Write-Status "running" "Download in progress..." 40
    } else {
        Write-Status "missing" "Offline TTS is not installed." 0
    }
    exit 0
}

if (Get-TtsReady) {
    Write-Status "ready" "Already installed." 100
    exit 0
}

if (Test-Path -LiteralPath $LockFile) {
    $lockPid = 0
    try {
        $rawLock = (Get-Content -LiteralPath $LockFile -TotalCount 1 -ErrorAction SilentlyContinue)
        [void][int]::TryParse("$rawLock", [ref]$lockPid)
    } catch {}
    $lockAlive = $false
    if ($lockPid -gt 0) {
        $lockAlive = [bool](Get-Process -Id $lockPid -ErrorAction SilentlyContinue)
    }
    if ($lockAlive) {
        Write-Status "running" "Уже идёт установка Silero..." 30
        exit 0
    }
    Remove-Item -LiteralPath $LockFile -Force -ErrorAction SilentlyContinue
}

if (-not (Test-Path -LiteralPath $FetchScript)) {
    Write-Status "error" ("Нет скрипта установки: " + $FetchScript) 0
    exit 1
}

Set-Content -LiteralPath $LockFile -Value $PID -Encoding ASCII
if (Test-BundledSilero) {
    Write-Status "running" "Копирую встроенный Silero (без интернета)..." 8
} else {
    Write-Status "running" "Скачиваю Silero (~500 МБ, 5-20 мин)..." 5
}
Remove-Item -LiteralPath $LogFile -Force -ErrorAction SilentlyContinue

$fetchEsc = $FetchScript.Replace("'", "''")
$logEsc = $LogFile.Replace("'", "''")
$runBody = @"
`$ErrorActionPreference = 'Continue'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File '$fetchEsc' *>> '$logEsc'
exit `$LASTEXITCODE
"@
Set-Content -LiteralPath $WrapperPs1 -Value $runBody -Encoding ASCII

try {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$WrapperPs1`""
    $psi.WorkingDirectory = $AppRoot
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    [void]$p.Start()

    $pct = 8
    $lastMsg = "Скачиваю / ставлю Silero..."
    while (-not $p.HasExited) {
        Start-Sleep -Seconds 2
        if (Test-Path -LiteralPath $LogFile) {
            try {
                $tailLines = @(Get-Content -LiteralPath $LogFile -Tail 20 -ErrorAction SilentlyContinue)
                foreach ($tl in $tailLines) {
                    $mapped = Map-StepPercent "$tl"
                    if ($mapped -ge 0 -and $mapped -gt $pct) { $pct = $mapped }
                    $trim = ("$tl").Trim()
                    if ($trim.Length -gt 0) {
                        if ($trim -match '(?i)copy-bundled|copying bundled') {
                            $lastMsg = "Копирую встроенный Silero (без интернета)..."
                        } elseif ($trim -match '(?i)ok silero ready \(copied') {
                            $lastMsg = "Silero скопирован. Проверяю..."
                        } else {
                            $lastMsg = $trim
                            if ($lastMsg.Length -gt 160) { $lastMsg = $lastMsg.Substring(0, 160) }
                        }
                    }
                }
            } catch {}
        }
        if ($pct -lt 88) { $pct = [Math]::Min(88, $pct + 1) }
        Write-Status "running" $lastMsg $pct
    }

    $exit = $p.ExitCode
    $tail = ""
    try {
        if (Test-Path -LiteralPath $LogFile) {
            $tail = ((Get-Content -LiteralPath $LogFile -Tail 30 -ErrorAction SilentlyContinue) -join " | ")
        }
    } catch {}

    if ($exit -ne 0 -or -not (Get-TtsReady)) {
        Write-Status "error" (Humanize-Error $tail) 0
        exit 1
    }

    Write-Status "ready" "Silero установлен." 100
    exit 0
} catch {
    Write-Status "error" (Humanize-Error $_.Exception.Message) 0
    exit 1
} finally {
    Remove-Item -LiteralPath $LockFile -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $WrapperPs1 -Force -ErrorAction SilentlyContinue
}
