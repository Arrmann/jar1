# Durable LED strip OFF timer. Survives parent exit; polls due_unix in config.
param(
    [Parameter(Mandatory = $true)]
    [int64]$DueUnix,

    [string]$TimerId = ""
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_jarvis-data-dir.ps1")
$dataDir = Get-JarvisDataDir
$cfgPath = Join-Path $dataDir "led-strip.json"
$python = Join-Path $PSScriptRoot "..\tts\runtime\python\python.exe"
$ledScript = Join-Path $PSScriptRoot "led-strip-ble.py"

function Read-Cfg {
    if (-not (Test-Path -LiteralPath $cfgPath)) { return $null }
    try {
        $raw = [IO.File]::ReadAllBytes($cfgPath)
        if ($raw.Length -ge 3 -and $raw[0] -eq 0xEF -and $raw[1] -eq 0xBB -and $raw[2] -eq 0xBF) {
            $raw = $raw[3..($raw.Length - 1)]
        }
        return ([Text.Encoding]::UTF8.GetString($raw) | ConvertFrom-Json)
    } catch { return $null }
}

function Save-CfgWithoutTimer([object]$cfg) {
    if ($null -eq $cfg) { return }
    $ht = @{}
    foreach ($p in $cfg.PSObject.Properties) {
        if ($p.Name -in @("timer_off_unix", "timer_id", "timer_hours", "timer_seconds")) { continue }
        $ht[$p.Name] = $p.Value
    }
    try {
        $utf8 = New-Object System.Text.UTF8Encoding $false
        [IO.File]::WriteAllText($cfgPath, (($ht | ConvertTo-Json -Depth 6) + "`n"), $utf8)
    } catch {}
}

function Still-Active {
    $cfg = Read-Cfg
    if ($null -eq $cfg) { return $false }
    if (-not $cfg.timer_off_unix) { return $false }
    if ([int64]$cfg.timer_off_unix -ne $DueUnix) { return $false }
    if ($TimerId -and $cfg.timer_id -and ("$($cfg.timer_id)" -ne $TimerId)) { return $false }
    return $true
}

while ($true) {
    if (-not (Still-Active)) { exit 0 }
    $now = [int64]([DateTime]::UtcNow - [datetime]'1970-01-01').TotalSeconds
    if ($DueUnix -le $now) { break }
    $sleepMs = [Math]::Min(2000, [Math]::Max(200, ($DueUnix - $now) * 1000))
    Start-Sleep -Milliseconds $sleepMs
}

if (-not (Still-Active)) { exit 0 }

if ((Test-Path -LiteralPath $python) -and (Test-Path -LiteralPath $ledScript)) {
    $env:JARVIS_CONFIG_DIR = $dataDir
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $python
    $psi.Arguments = "`"$ledScript`" off --direct"
    $psi.WorkingDirectory = (Split-Path -Parent $PSScriptRoot)
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $process = [System.Diagnostics.Process]::Start($psi)
    $process.WaitForExit()
}

Save-CfgWithoutTimer (Read-Cfg)
exit 0
