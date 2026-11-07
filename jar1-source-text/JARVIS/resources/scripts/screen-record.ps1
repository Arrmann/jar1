param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("start", "stop", "status")]
    [string]$Action
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_jarvis-data-dir.ps1")
$DataDir = Get-JarvisDataDir
$PidFile = Join-Path $DataDir "screen-record.pid"
$ActiveFlag = Join-Path $DataDir "screen-record.active"
$OutFileMeta = Join-Path $DataDir "screen-record.out"
$WatcherFlag = Join-Path $DataDir "screen-record.watch"
$StopFlag = Join-Path $DataDir "screen-record.stop"
$HudPidFile = Join-Path $DataDir "screen-record.hud.pid"

if (-not (Test-Path $DataDir)) {
    New-Item -ItemType Directory -Path $DataDir -Force | Out-Null
}

function Find-Ffmpeg {
    $root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $candidates = @(
        (Join-Path $root "tools\ffmpeg\ffmpeg.exe"),
        (Join-Path $PSScriptRoot "..\..\tools\ffmpeg\ffmpeg.exe"),
        (Join-Path $PSScriptRoot "..\..\tools\ffmpeg\ffmpeg-9.0-essentials_build\bin\ffmpeg.exe"),
        (Join-Path $PWD "tools\ffmpeg\ffmpeg.exe")
    )
    foreach ($c in $candidates) {
        try {
            $full = [IO.Path]::GetFullPath($c)
            if (Test-Path -LiteralPath $full) { return $full }
        } catch {}
    }
    $cmd = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Notify([string]$title, [string]$msg) {
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
        $n = New-Object System.Windows.Forms.NotifyIcon
        $n.Icon = [System.Drawing.SystemIcons]::Information
        $n.Visible = $true
        $n.BalloonTipTitle = $title
        $n.BalloonTipText = $msg
        $n.ShowBalloonTip(4000)
        Start-Sleep -Milliseconds 500
        $n.Dispose()
    } catch {
        Write-Host ($title + " - " + $msg)
    }
}

function Get-RecordingPid {
    if (-not (Test-Path -LiteralPath $PidFile)) { return $null }
    $raw = (Get-Content -LiteralPath $PidFile -ErrorAction SilentlyContinue | Select-Object -First 1)
    $pidNum = 0
    if (-not [int]::TryParse("$raw", [ref]$pidNum)) { return $null }
    try {
        $p = Get-Process -Id $pidNum -ErrorAction Stop
        if ($p.HasExited) { return $null }
        return $pidNum
    } catch {}
    return $null
}

function Stop-Hud {
    Remove-Item -LiteralPath $ActiveFlag -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $HudPidFile) {
        $hid = 0
        $raw = (Get-Content -LiteralPath $HudPidFile -Raw -ErrorAction SilentlyContinue)
        if ([int]::TryParse(($raw + "").Trim(), [ref]$hid) -and $hid -gt 0) {
            Stop-Process -Id $hid -Force -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $HudPidFile -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-WinAltR {
    if (-not ("JarvisScreenKeys" -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class JarvisScreenKeys {
  [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
  public const uint KEYEVENTF_KEYUP = 0x0002;
  public const byte VK_LWIN = 0x5B;
  public const byte VK_ALT = 0x12;
  public const byte VK_R = 0x52;
  public static void ChordWinAltR() {
    keybd_event(VK_LWIN, 0, 0, UIntPtr.Zero);
    keybd_event(VK_ALT, 0, 0, UIntPtr.Zero);
    keybd_event(VK_R, 0, 0, UIntPtr.Zero);
    keybd_event(VK_R, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
    keybd_event(VK_ALT, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
    keybd_event(VK_LWIN, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
  }
}
"@
    }
    [JarvisScreenKeys]::ChordWinAltR()
}

function Start-F12Watcher {
    $watchScript = Join-Path $PSScriptRoot "screen-record-f12-watch.ps1"
    if (-not (Test-Path -LiteralPath $watchScript)) { return }
    Set-Content -LiteralPath $WatcherFlag -Value "1" -Encoding ASCII
    Start-Process -FilePath "powershell.exe" -ArgumentList @(
        "-NoProfile", "-STA", "-ExecutionPolicy", "Bypass",
        "-File", $watchScript
    ) | Out-Null
}

function Wait-HostStop([int]$PidNum, [int]$TimeoutMs) {
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    Set-Content -LiteralPath $StopFlag -Value "1" -Encoding ASCII
    while ([DateTime]::UtcNow -lt $deadline) {
        try {
            $p = Get-Process -Id $PidNum -ErrorAction Stop
            if ($p.HasExited) { return $true }
        } catch {
            return $true
        }
        Start-Sleep -Milliseconds 150
    }
    try { Stop-Process -Id $PidNum -Force -ErrorAction SilentlyContinue } catch {}
    return $false
}

function Stop-Recording {
    $pidNum = Get-RecordingPid
    $outPath = $null
    if (Test-Path -LiteralPath $OutFileMeta) {
        $outPath = (Get-Content -LiteralPath $OutFileMeta -Raw -ErrorAction SilentlyContinue).Trim()
    }
    if ($null -ne $pidNum) {
        Wait-HostStop -PidNum $pidNum -TimeoutMs 12000 | Out-Null
    }
    Stop-Hud
    Remove-Item -LiteralPath $PidFile, $WatcherFlag, $StopFlag -Force -ErrorAction SilentlyContinue

    if ($outPath -and (Test-Path -LiteralPath $outPath)) {
        $len = (Get-Item -LiteralPath $outPath).Length
        if ($len -gt 2048) {
            $short = $outPath
            if ($short.Length -gt 72) { $short = "..." + $short.Substring($short.Length - 68) }
            Notify "JARVIS" ("Saved MP4: " + $short)
            Write-Output ("OK:STOPPED|" + $outPath)
            return
        }
    }
    Notify "JARVIS" "Screen recording stopped"
    Write-Output "OK:STOPPED"
}

function Start-GameBarFallback {
    Invoke-WinAltR
    Set-Content -LiteralPath $ActiveFlag -Value "gamebar" -Encoding ASCII
    Notify "JARVIS" "Game Bar recording - F12 or voice stop"
    Start-F12Watcher
    Write-Output "OK:STARTED|gamebar"
}

if ($Action -eq "status") {
    $pidNum = Get-RecordingPid
    if ($null -ne $pidNum -or (Test-Path -LiteralPath $ActiveFlag)) {
        Write-Output "OK:RECORDING"
        exit 0
    }
    Write-Output "OK:IDLE"
    exit 0
}

if ($Action -eq "stop") {
    $wasGameBar = $false
    if (Test-Path -LiteralPath $ActiveFlag) {
        $flagText = Get-Content -LiteralPath $ActiveFlag -Raw -ErrorAction SilentlyContinue
        if ($flagText -match "gamebar") { $wasGameBar = $true }
    }
    if ($wasGameBar) {
        Invoke-WinAltR
        Stop-Hud
        Remove-Item -LiteralPath $PidFile, $ActiveFlag, $WatcherFlag, $StopFlag -Force -ErrorAction SilentlyContinue
        Notify "JARVIS" "Game Bar recording stopped"
        Write-Output "OK:STOPPED|gamebar"
        exit 0
    }
    Stop-Recording
    exit 0
}

# start
$existing = Get-RecordingPid
if ($null -ne $existing) {
    Notify "JARVIS" "Already recording - F12 or voice stop"
    Write-Output "OK:ALREADY"
    exit 0
}
if (Test-Path -LiteralPath $ActiveFlag) {
    Remove-Item -LiteralPath $ActiveFlag, $PidFile, $WatcherFlag, $StopFlag -Force -ErrorAction SilentlyContinue
}

$ffmpeg = Find-Ffmpeg
if (-not $ffmpeg) {
    Start-GameBarFallback
    exit 0
}

$videos = Join-Path $env:USERPROFILE "Videos\JARVIS-Recordings"
if (-not (Test-Path $videos)) {
    New-Item -ItemType Directory -Path $videos -Force | Out-Null
}
$stamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$outPath = Join-Path $videos ("JARVIS_" + $stamp + ".mp4")
Set-Content -LiteralPath $OutFileMeta -Value $outPath -Encoding UTF8

$hostScript = Join-Path $PSScriptRoot "screen-record-host.ps1"
if (-not (Test-Path -LiteralPath $hostScript)) {
    Start-GameBarFallback
    exit 0
}

Remove-Item -LiteralPath $StopFlag -Force -ErrorAction SilentlyContinue
Set-Content -LiteralPath $WatcherFlag -Value "1" -Encoding ASCII
$recHostProc = Start-Process -FilePath "powershell.exe" -PassThru -ArgumentList @(
    "-NoProfile", "-STA", "-ExecutionPolicy", "Bypass",
    "-File", $hostScript,
    "-OutPath", $outPath,
    "-FfmpegPath", $ffmpeg,
    "-DataDir", $DataDir
)

if ($null -eq $recHostProc) {
    Start-GameBarFallback
    exit 0
}

Start-Sleep -Milliseconds 1800
if ($recHostProc.HasExited) {
    Start-GameBarFallback
    exit 0
}

Set-Content -LiteralPath $PidFile -Value ("{0}" -f $recHostProc.Id) -Encoding ASCII
Start-F12Watcher
Notify "JARVIS" "Screen recording - red REC on top - F12 to stop"
Write-Output ("OK:STARTED|" + $outPath)
exit 0
