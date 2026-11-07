param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("on", "off", "toggle", "list-cameras")]
    [string]$Action
)

# ASCII-only script: Windows PowerShell 5.1 breaks on UTF-8 without BOM (ellipsis/dashes).
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_jarvis-data-dir.ps1")
. (Join-Path $PSScriptRoot "_jarvis-hidden-process.ps1")
$env:PYTHONIOENCODING = "utf-8"
$env:PYTHONUTF8 = "1"
# Do not write __pycache__ into install dir (Program Files / portable tree).
$env:PYTHONDONTWRITEBYTECODE = "1"

# resources/scripts -> package root
$exeDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = (Resolve-Path (Join-Path $exeDir "..\..")).Path
$gestDir = Join-Path $root "resources\gestures"
$engine = Join-Path $gestDir "jarvis_gestures.py"
$req = Join-Path $gestDir "requirements.txt"
$bundledSite = Join-Path $gestDir "site-packages"
$wheelsDir = Join-Path $gestDir "wheels"
$settingsDir = Get-JarvisDataDir
$stopFile = Join-Path $settingsDir "gestures.stop"
$pidFile = Join-Path $settingsDir "gestures.pid"
$settingsFile = Join-Path $settingsDir "app.db"
$statusFile = Join-Path $settingsDir "gestures_status.json"
$legacyStop = Join-Path $root "gestures.stop"

function Resolve-Python {
    # Prefer ONLY the Python shipped with JARVIS (same ABI as bundled wheels).
    $candidates = @()
    if ($env:JARVIS_PYTHON) { $candidates += $env:JARVIS_PYTHON }
    $candidates += @(
        (Join-Path $root "resources\tts\runtime\python\pythonw.exe"),
        (Join-Path $root "resources\tts\runtime\python\python.exe")
    )
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        foreach ($c in $candidates) {
            if (-not $c -or -not (Test-Path -LiteralPath $c)) { continue }
            $probe = $c
            if ($c -match 'pythonw\.exe$') {
                $probe = ($c -replace 'pythonw\.exe$', 'python.exe')
                if (-not (Test-Path -LiteralPath $probe)) { $probe = $c }
            }
            $ver = (Invoke-JarvisHiddenOutput -FilePath $probe -ArgumentList @("--version")).Output
            if ("$ver" -match "Python 3\.(10|11|12)") { return $c }
        }
    } finally {
        $ErrorActionPreference = $prevEap
    }
    return $null
}

function Get-GesturePids {
    $pids = New-Object System.Collections.Generic.List[int]
    if (Test-Path -LiteralPath $pidFile) {
        $raw = (Get-Content -LiteralPath $pidFile -ErrorAction SilentlyContinue | Select-Object -First 1)
        $p = 0
        if ([int]::TryParse($raw, [ref]$p) -and $p -gt 0) {
            $proc = Get-Process -Id $p -ErrorAction SilentlyContinue
            if ($proc) { [void]$pids.Add($p) }
        }
    }
    Get-CimInstance Win32_Process -Filter "Name = 'python.exe' OR Name = 'pythonw.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine -like "*jarvis_gestures.py*" } |
        ForEach-Object {
            if (-not $pids.Contains([int]$_.ProcessId)) {
                [void]$pids.Add([int]$_.ProcessId)
            }
        }
    return @($pids)
}

function Get-GesturePid {
    $all = @(Get-GesturePids)
    if ($all.Count -gt 0) { return $all[0] }
    return $null
}

function Write-Utf8NoBom([string]$Path, [string]$Content) {
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($Path, $Content, $utf8)
}

function Read-SettingsObject {
    if (-not (Test-Path $settingsFile)) { return $null }
    $raw = [System.IO.File]::ReadAllText($settingsFile)
    if ($raw.Length -gt 0 -and [int][char]$raw[0] -eq 0xFEFF) {
        $raw = $raw.Substring(1)
    }
    try {
        return ($raw | ConvertFrom-Json)
    } catch {
        return $null
    }
}

function Set-GesturesEnabledFlag([bool]$Enabled) {
    if (-not (Test-Path $settingsDir)) {
        New-Item -ItemType Directory -Path $settingsDir | Out-Null
    }
    $obj = Read-SettingsObject
    if ($null -eq $obj) { return }
    if ($obj.PSObject.Properties.Name -contains "gestures_enabled") {
        $obj.gestures_enabled = $Enabled
    } else {
        $obj | Add-Member -NotePropertyName gestures_enabled -NotePropertyValue $Enabled -Force
    }
    Write-Utf8NoBom -Path $settingsFile -Content ($obj | ConvertTo-Json -Depth 20)
}

function Sync-CameraPreference {
    $pref = $env:JARVIS_GESTURES_CAMERA
    if (-not $pref) {
        $obj = Read-SettingsObject
        if ($null -ne $obj -and $obj.PSObject.Properties.Name -contains "gestures_camera" -and $obj.gestures_camera) {
            $pref = [string]$obj.gestures_camera
        }
    }
    if (-not $pref) { $pref = "auto" }
    $pref = $pref.Trim().ToLowerInvariant()
    if (-not (Test-Path $settingsDir)) {
        New-Item -ItemType Directory -Path $settingsDir | Out-Null
    }
    $camFile = Join-Path $settingsDir "gestures_camera.txt"
    Write-Utf8NoBom -Path $camFile -Content $pref
    $env:JARVIS_GESTURES_CAMERA = $pref
    return $pref
}

function Set-PythonPath([string]$Site) {
    if (-not $Site -or -not (Test-Path -LiteralPath $Site)) { return }
    if ($env:PYTHONPATH) {
        if ($env:PYTHONPATH -notlike "*$Site*") {
            $env:PYTHONPATH = "$Site;$env:PYTHONPATH"
        }
    } else {
        $env:PYTHONPATH = $Site
    }
}

function Test-GestureImports([string]$Probe) {
    # Embeddable Python ignores PYTHONPATH. Mirror jarvis_gestures._bootstrap_offline_site
    # so a broken bundled numpy fails here instead of after the camera process starts.
    # Win32 calls go through ctypes; pywin32 / psutil are not required.
    $code = @"
import sys
from pathlib import Path
site = Path(r'''$bundledSite''')
for p in (site, site / 'win32', site / 'win32' / 'lib', site / 'Pythonwin'):
    if not p.is_dir():
        continue
    s = str(p)
    while s in sys.path:
        sys.path.remove(s)
    sys.path.insert(0, s)
import numpy, cv2, mediapipe, websocket
assert numpy.__version__.startswith('1.'), numpy.__version__
"@
    $r = Invoke-JarvisHiddenOutput -FilePath $Probe -ArgumentList @("-c", $code)
    return ($r.ExitCode -eq 0)
}

function Install-FromWheels([string]$Probe, [string]$UserBase) {
    if (-not (Test-Path -LiteralPath $wheelsDir)) { return $false }
    $whls = @(Get-ChildItem -LiteralPath $wheelsDir -Filter "*.whl" -ErrorAction SilentlyContinue)
    if ($whls.Count -lt 3) { return $false }
    New-Item -ItemType Directory -Path $UserBase -Force | Out-Null
    $env:PYTHONUSERBASE = $UserBase
    $pipLog = Join-Path $settingsDir "gestures-pip.log"
    # Offline install from shipped wheels (no network).
    $r = Invoke-JarvisHiddenOutput -FilePath $Probe -ArgumentList @(
        "-m", "pip", "install", "--user", "--disable-pip-version-check",
        "--no-index", "--find-links", $wheelsDir, "-r", $req
    )
    try { [IO.File]::WriteAllText($pipLog, [string]$r.Output) } catch {}
    return ($r.ExitCode -eq 0)
}

function Ensure-Deps([string]$Py) {
    $probe = $Py
    if ($Py -match 'pythonw\.exe$') {
        $probe = ($Py -replace 'pythonw\.exe$', 'python.exe')
        if (-not (Test-Path -LiteralPath $probe)) { $probe = $Py }
    }

    $userBase = Join-Path $settingsDir "py-user"
    $userSite = Join-Path $userBase "Lib\site-packages"

    # 1) Bundled offline site-packages (best: works on every PC without network/pip)
    Set-PythonPath $bundledSite
    # 2) Previously installed user site
    Set-PythonPath $userSite
    $env:PYTHONUSERBASE = $userBase

    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        if (Test-GestureImports $probe) { return }

        # 3) Install from local wheels into %APPDATA%\...\py-user (offline).
        # Never pip from the internet on customer PCs (PyPI/mediapipe is slow,
        # ABI-fragile, and often blocked).
        if (Install-FromWheels $probe $userBase) {
            Set-PythonPath $userSite
            if (Test-GestureImports $probe) { return }
        }

        $tail = ""
        $pipLog = Join-Path $settingsDir "gestures-pip.log"
        if (Test-Path -LiteralPath $pipLog) {
            $tail = ((Get-Content -LiteralPath $pipLog -Tail 6) -join " | ")
        }
        throw "Gesture libraries missing. Reinstall JARVIS (needs resources/gestures/site-packages). $tail"
    } finally {
        $ErrorActionPreference = $prevEap
    }
}

function Stop-Gestures {
    if (-not (Test-Path $settingsDir)) {
        New-Item -ItemType Directory -Path $settingsDir | Out-Null
    }
    # Stop signal lives only under %APPDATA% (writable). Never write
    # <install>\gestures.stop — under Program Files a non-admin cannot delete it,
    # and the engine used to treat that leftover as a permanent "off".
    Set-Content -Path $stopFile -Value "1" -Encoding ASCII -Force
    Remove-Item -Force $legacyStop -ErrorAction SilentlyContinue

    $deadline = (Get-Date).AddSeconds(2.5)
    while ((Get-Date) -lt $deadline) {
        $alive = @(Get-GesturePids)
        if ($alive.Count -eq 0) { break }
        Start-Sleep -Milliseconds 150
    }

    foreach ($p in @(Get-GesturePids)) {
        Stop-Process -Id $p -Force -ErrorAction SilentlyContinue
        try {
            Invoke-JarvisHiddenOutput -FilePath "taskkill.exe" -ArgumentList @("/PID", "$p", "/F", "/T") | Out-Null
        } catch {}
    }
    Get-Process -Name "jarvis-gestures" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

    Remove-Item -Force $stopFile -ErrorAction SilentlyContinue
    Remove-Item -Force $legacyStop -ErrorAction SilentlyContinue
    Remove-Item -Force $pidFile -ErrorAction SilentlyContinue
    Write-Utf8NoBom -Path $statusFile -Content '{"active":false,"camera":false,"backend":"","last_gesture":"","message":"stopped"}'
}

if ($Action -eq "list-cameras") {
    $py = Resolve-Python
    if (-not $py) {
        Write-Output '{"cameras":[],"preferred":"auto","error":"bundled python missing"}'
        exit 1
    }
    $probe = $py
    if ($py -match 'pythonw\.exe$') {
        $probe = ($py -replace 'pythonw\.exe$', 'python.exe')
        if (-not (Test-Path -LiteralPath $probe)) { $probe = $py }
    }
    try { Ensure-Deps $probe } catch {
        Write-Output (@{ cameras = @(); preferred = "auto"; error = [string]$_.Exception.Message } | ConvertTo-Json -Compress -Depth 6)
        exit 1
    }
    $env:JARVIS_CONFIG_DIR = $settingsDir
    [void](Sync-CameraPreference)
    # OpenCV MSMF prints WARN on stderr; PS 5.1 + Stop treats that as terminating.
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $cam = Invoke-JarvisHiddenOutput -FilePath $probe -ArgumentList @("-u", $engine, "--list-cameras")
        $out = $cam.Output
        $code = $cam.ExitCode
    } finally {
        $ErrorActionPreference = $prevEap
    }
    if ($code -ne 0 -or -not $out) {
        Write-Output '{"cameras":[],"preferred":"auto","error":"probe failed"}'
        exit 1
    }
    Write-Output ($out | Out-String).Trim()
    exit 0
}

$runningPid = Get-GesturePid
$running = [bool]$runningPid
$target = switch ($Action) {
    "on" { $true }
    "off" { $false }
    "toggle" { -not $running }
}

if ($target) {
    if (-not (Test-Path -LiteralPath $engine)) {
        Write-Error "Missing $engine - reinstall JARVIS."
        exit 1
    }
    $modelTask = Join-Path $gestDir "hand_landmarker.task"
    if (-not (Test-Path -LiteralPath $modelTask) -or ((Get-Item -LiteralPath $modelTask).Length -lt 100000)) {
        Write-Error "Missing hand_landmarker.task in resources\gestures - reinstall JARVIS."
        exit 1
    }
    $py = Resolve-Python
    if (-not $py) {
        Write-Error "Bundled Python missing (resources\tts\runtime\python). Reinstall JARVIS."
        exit 1
    }
    try {
        Ensure-Deps $py
    } catch {
        $msg = [string]$_.Exception.Message
        if ($msg.Length -gt 180) { $msg = $msg.Substring(0, 180) }
        $payload = @{
            active = $false
            camera = $false
            backend = ""
            last_gesture = ""
            message = "deps: $msg"
        } | ConvertTo-Json -Compress
        Write-Utf8NoBom -Path $statusFile -Content $payload
        Write-Error $_
        exit 1
    }
    if ($running) {
        Set-GesturesEnabledFlag $true
        Write-Output "gestures on (already running)"
        exit 0
    }
    Remove-Item -Force $stopFile -ErrorAction SilentlyContinue
    Remove-Item -Force $legacyStop -ErrorAction SilentlyContinue
    $env:JARVIS_CONFIG_DIR = $settingsDir
    [void](Sync-CameraPreference)
    # Keep PYTHONPATH for child process
    $p = Start-JarvisHiddenProcess -FilePath $py -ArgumentList @("-u", $engine) -WorkingDirectory $root
    $ok = $false
    for ($i = 0; $i -lt 25; $i++) {
        Start-Sleep -Milliseconds 400
        if (-not (Get-Process -Id $p.Id -ErrorAction SilentlyContinue)) { break }
        if (Test-Path -LiteralPath $statusFile) {
            try {
                $st = Get-Content -LiteralPath $statusFile -Raw | ConvertFrom-Json
                if ($st.camera -eq $true -and $st.active -eq $true) { $ok = $true; break }
                if ($st.message -and ($st.message -match 'no camera|camera error|deps|mediapipe init|missing')) {
                    Write-Error "Gesture engine: $($st.message)"
                    exit 1
                }
            } catch {}
        }
    }
    if (-not (Get-Process -Id $p.Id -ErrorAction SilentlyContinue)) {
        $hint = "Check camera privacy (Windows Settings > Privacy > Camera) and allow desktop apps."
        if (Test-Path -LiteralPath $statusFile) {
            try {
                $st = Get-Content -LiteralPath $statusFile -Raw | ConvertFrom-Json
                if ($st.message) { $hint = [string]$st.message }
            } catch {}
        }
        Write-Error "MediaPipe gesture engine exited. $hint"
        exit 1
    }
    Write-Utf8NoBom -Path $pidFile -Content "$($p.Id)"
    Set-GesturesEnabledFlag $true
    if ($ok) {
        Write-Output 'gestures on (mediapipe camera ok)'
    } else {
        Write-Output 'gestures on (mediapipe starting)'
    }
    exit 0
}

Stop-Gestures
Set-GesturesEnabledFlag $false
Write-Output "gestures off"
exit 0
