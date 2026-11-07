# Stop leftover JARVIS processes so a clean one-click start can bind IPC.
# Never kill foreign PIDs on 9712-9722 (ghost sockets are skipped via port fallback).
param(
    [switch]$KeepGui
)

$ErrorActionPreference = "SilentlyContinue"
# A cold engine has no listening port yet. Never reclaim a live startup owner.
$startingProbe = Join-Path $PSScriptRoot 'jarvis-engine-starting.ps1'
if (Test-Path -LiteralPath $startingProbe) {
    & $startingProbe
    if ($LASTEXITCODE -eq 0) { exit 0 }
}
$names = @("jarvis-app", "jarvis-run", "jarvis-gestures")
if (-not $KeepGui) { $names += "jarvis-gui" }

foreach ($n in $names) {
    Get-Process -Name $n -ErrorAction SilentlyContinue | ForEach-Object {
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    }
    & taskkill.exe /F /IM "$n.exe" >$null 2>&1
}

# MediaPipe product path: python* running jarvis_gestures.py
try {
    Get-CimInstance Win32_Process -Filter "Name='python.exe' OR Name='pythonw.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like '*jarvis_gestures.py*' } |
        ForEach-Object {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
            & taskkill.exe /F /PID $_.ProcessId >$null 2>&1
        }
} catch {}

# Only reclaim ports still owned by JARVIS images (never random apps).
for ($port = 9712; $port -le 9722; $port++) {
    try {
        $owners = @(Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty OwningProcess -Unique |
            Where-Object { $_ -and $_ -gt 0 })
        foreach ($procId in $owners) {
            $proc = Get-Process -Id $procId -ErrorAction SilentlyContinue
            if (-not $proc) { continue }
            $stem = $proc.ProcessName.ToLowerInvariant()
            if ($names -contains $stem) {
                Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
                & taskkill.exe /F /PID $procId >$null 2>&1
            }
        }
    } catch {}
}

# Clear stale IPC files under the active data dir and the current bundle dir.
. (Join-Path $PSScriptRoot "_jarvis-data-dir.ps1")
$configDirs = @()
if ($env:JARVIS_CONFIG_DIR) { $configDirs += $env:JARVIS_CONFIG_DIR }
$configDirs += (Get-JarvisDataDir)
if ($env:APPDATA) {
    $configDirs += (Join-Path $env:APPDATA "com.jarvisn.assistant")
    $configDirs += (Join-Path $env:APPDATA "com.priler.jarvis")
}
foreach ($dir in ($configDirs | Select-Object -Unique)) {
    Remove-Item -Force (Join-Path $dir "ipc.port") -ErrorAction SilentlyContinue
    Remove-Item -Force (Join-Path $dir "ipc.token") -ErrorAction SilentlyContinue
}

Start-Sleep -Milliseconds 350
exit 0
