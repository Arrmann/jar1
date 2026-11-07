# Native JARVIS dictation (STT -> Ctrl+V). No Win+H.
# start: flag + ignore window + 10 min hard deadline + Esc watcher
# stop: clear
# type: paste text (skipped by engine for trigger words)
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet("start", "stop", "type", "status")]
    [string]$Action,
    [Parameter(Position = 1)]
    [string]$Text = ""
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_jarvis-data-dir.ps1")
$dataDir = Get-JarvisDataDir
New-Item -ItemType Directory -Force -Path $dataDir | Out-Null
$flag = Join-Path $dataDir "dictate.active"
$ignoreFile = Join-Path $dataDir "dictate.ignore_until"
$deadlineFile = Join-Path $dataDir "dictate.deadline"
$watchPidFile = Join-Path $dataDir "dictate.watch.pid"
$stoppedFile = Join-Path $dataDir "dictate.stopped"

function Stop-EscWatcher {
    if (Test-Path -LiteralPath $watchPidFile) {
        $raw = (Get-Content -LiteralPath $watchPidFile -Raw -ErrorAction SilentlyContinue)
        $wid = 0
        if ([int]::TryParse(($raw + "").Trim(), [ref]$wid) -and $wid -gt 0) {
            Stop-Process -Id $wid -Force -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $watchPidFile -Force -ErrorAction SilentlyContinue
    }
    Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like "*dictate-esc-watch.ps1*" } |
        ForEach-Object {
            try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch {}
        }
}

function Ensure-KeyType {
    if (-not ("JarvisDictateInput" -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class JarvisDictateInput {
  [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
  public const uint KEYEVENTF_KEYUP = 0x0002;
  public static void Chord(params byte[] keys) {
    foreach (var k in keys) keybd_event(k, 0, 0, UIntPtr.Zero);
    for (int i = keys.Length - 1; i >= 0; i--) keybd_event(keys[i], 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
  }
}
"@
    }
}

function Clear-Session {
    Stop-EscWatcher
    foreach ($f in @($flag, $ignoreFile, $deadlineFile)) {
        if (Test-Path -LiteralPath $f) {
            Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
        }
    }
}

function Signal-DictateStopped {
    Set-Content -LiteralPath $stoppedFile -Value "1" -Encoding ASCII -ErrorAction SilentlyContinue
}

switch ($Action) {
    "status" {
        if (Test-Path -LiteralPath $flag) { Write-Output "active"; exit 0 }
        Write-Output "idle"
        exit 0
    }
    "start" {
        Stop-EscWatcher
        Remove-Item -LiteralPath $stoppedFile -Force -ErrorAction SilentlyContinue
        $now = [DateTimeOffset]::UtcNow
        # Ignore echo of the trigger phrase for 2.5s (PS 5.1-safe ms epoch)
        $ignoreUntil = [int64](($now.UtcDateTime.AddMilliseconds(2500) - [datetime]'1970-01-01').TotalMilliseconds)
        $deadline = [int64](($now.UtcDateTime.AddMinutes(10) - [datetime]'1970-01-01').TotalMilliseconds)
        Set-Content -LiteralPath $flag -Value ($now.ToString("o")) -Encoding UTF8
        Set-Content -LiteralPath $ignoreFile -Value ([string]$ignoreUntil) -Encoding ASCII
        Set-Content -LiteralPath $deadlineFile -Value ([string]$deadline) -Encoding ASCII
        $watch = Join-Path $PSScriptRoot "dictate-esc-watch.ps1"
        if (Test-Path -LiteralPath $watch) {
            $p = Start-Process -FilePath "powershell.exe" -PassThru -ArgumentList @(
                "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", $watch
            )
            Set-Content -LiteralPath $watchPidFile -Value ([string]$p.Id) -Encoding ASCII
        }
        Write-Host "JARVIS dictate: start (30 sec idle, 10 min max)"
    }
    "stop" {
        Clear-Session
        Signal-DictateStopped
        Write-Host "JARVIS dictate: stop"
    }
    "type" {
        if ([string]::IsNullOrWhiteSpace($Text)) { exit 0 }
        # Soft-gate: still respect ignore window if engine missed it
        if (Test-Path -LiteralPath $ignoreFile) {
            $until = 0L
            $raw = (Get-Content -LiteralPath $ignoreFile -Raw -ErrorAction SilentlyContinue)
            if ([long]::TryParse(($raw + "").Trim(), [ref]$until)) {
                $nowMs = [int64](([DateTime]::UtcNow - [datetime]'1970-01-01').TotalMilliseconds)
                if ($nowMs -lt $until) {
                    Write-Host "JARVIS dictate: ignore echo"
                    exit 0
                }
            }
        }
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        $payload = $Text.Trim()
        if (-not $payload.EndsWith(" ")) { $payload = $payload + " " }
        try {
            [System.Windows.Forms.Clipboard]::SetText($payload)
        } catch {
            Set-Clipboard -Value $payload
        }
        Start-Sleep -Milliseconds 70
        Ensure-KeyType
        [JarvisDictateInput]::Chord(0x11, 0x56)
        Write-Host "JARVIS dictate: typed $($payload.Length) chars"
    }
}
exit 0
