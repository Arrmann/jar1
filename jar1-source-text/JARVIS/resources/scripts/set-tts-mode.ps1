# Set JARVIS TTS mode for end users.
# Usage:
#   set-tts-mode.ps1 ondemand
#   set-tts-mode.ps1 background
# Does NOT rewrite app.db (dual-process race). Engine/GUI read tts.mode + settings.
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet("ondemand", "background")]
    [string]$Mode
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_jarvis-data-dir.ps1")
$DataDir = Get-JarvisDataDir
New-Item -ItemType Directory -Force -Path $DataDir | Out-Null

# Atomic write of mode flag only (never patch whole app.db from PowerShell).
$modeFile = Join-Path $DataDir "tts.mode"
$tmp = Join-Path $DataDir ("tts.mode.tmp." + [guid]::NewGuid().ToString("N"))
try {
    [IO.File]::WriteAllText($tmp, $Mode + "`n", [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tmp -Destination $modeFile -Force
} finally {
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
}

$Ctl = Join-Path $PSScriptRoot "tts-worker-ctl.ps1"
if (Test-Path -LiteralPath $Ctl) {
    if ($Mode -eq "background") {
        & $Ctl -Action start
    } else {
        & $Ctl -Action stop
    }
}

Write-Host "TTS mode set to: $Mode"
exit 0
