# Host process: runs ffmpeg with graceful 'q' stop + keeps HUD alive.
param(
    [Parameter(Mandatory = $true)]
    [string]$OutPath,
    [Parameter(Mandatory = $true)]
    [string]$FfmpegPath,
    [Parameter(Mandatory = $true)]
    [string]$DataDir
)

$ErrorActionPreference = "SilentlyContinue"
$PidFile = Join-Path $DataDir "screen-record.pid"
$ActiveFlag = Join-Path $DataDir "screen-record.active"
$StopFlag = Join-Path $DataDir "screen-record.stop"
$WatchFlag = Join-Path $DataDir "screen-record.watch"
$HudPidFile = Join-Path $DataDir "screen-record.hud.pid"

Remove-Item -LiteralPath $StopFlag -Force -ErrorAction SilentlyContinue
Set-Content -LiteralPath $PidFile -Value ([string]$PID) -Encoding ASCII
Set-Content -LiteralPath $ActiveFlag -Value ((Get-Date).ToString("o")) -Encoding UTF8

# REC overlay
$hudScript = Join-Path $PSScriptRoot "screen-record-hud.ps1"
if (Test-Path -LiteralPath $hudScript) {
    Start-Process -FilePath "powershell.exe" -ArgumentList @(
        "-NoProfile", "-STA", "-ExecutionPolicy", "Bypass", "-File", $hudScript
    ) | Out-Null
}

Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
$screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$sizeArg = "{0}x{1}" -f $screen.Width, $screen.Height

function Quote-ProcessArg([string]$Text) {
    if ($Text -match '[\s"]') {
        return '"' + ($Text -replace '"', '\"') + '"'
    }
    return $Text
}

$ffArgs = @(
    "-hide_banner", "-loglevel", "warning", "-y",
    "-f", "gdigrab", "-draw_mouse", "1", "-framerate", "30",
    "-video_size", $sizeArg, "-i", "desktop",
    "-c:v", "libx264", "-preset", "veryfast", "-crf", "22",
    "-pix_fmt", "yuv420p", "-movflags", "+faststart",
    $OutPath
)

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $FfmpegPath
$psi.Arguments = (($ffArgs | ForEach-Object { Quote-ProcessArg $_ }) -join " ")
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $false
$psi.RedirectStandardError = $false
$psi.WorkingDirectory = Split-Path $FfmpegPath -Parent

$proc = $null
try {
    $proc = [System.Diagnostics.Process]::Start($psi)
} catch {
    Remove-Item -LiteralPath $ActiveFlag, $PidFile, $WatchFlag -Force -ErrorAction SilentlyContinue
    exit 2
}

if ($null -eq $proc) {
    Remove-Item -LiteralPath $ActiveFlag, $PidFile, $WatchFlag -Force -ErrorAction SilentlyContinue
    exit 2
}

Start-Sleep -Milliseconds 700
if ($proc.HasExited) {
    Remove-Item -LiteralPath $ActiveFlag, $PidFile, $WatchFlag -Force -ErrorAction SilentlyContinue
    exit 3
}

while (-not $proc.HasExited) {
    if (Test-Path -LiteralPath $StopFlag) { break }
    if (-not (Test-Path -LiteralPath $ActiveFlag)) { break }
    Start-Sleep -Milliseconds 120
}

try {
    if (-not $proc.HasExited) {
        try {
            $proc.StandardInput.WriteLine("q")
            $proc.StandardInput.Flush()
            $proc.StandardInput.Close()
        } catch {}
        if (-not $proc.WaitForExit(8000)) {
            try { $proc.Kill() } catch {}
        }
    }
} catch {
    try { if (-not $proc.HasExited) { $proc.Kill() } } catch {}
}

# Stop HUD
Remove-Item -LiteralPath $ActiveFlag -Force -ErrorAction SilentlyContinue
if (Test-Path -LiteralPath $HudPidFile) {
    $hid = 0
    $raw = (Get-Content -LiteralPath $HudPidFile -Raw -ErrorAction SilentlyContinue)
    if ([int]::TryParse(($raw + "").Trim(), [ref]$hid) -and $hid -gt 0) {
        Stop-Process -Id $hid -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath $HudPidFile -Force -ErrorAction SilentlyContinue
}

Remove-Item -LiteralPath $StopFlag, $WatchFlag, $PidFile -Force -ErrorAction SilentlyContinue
exit 0
