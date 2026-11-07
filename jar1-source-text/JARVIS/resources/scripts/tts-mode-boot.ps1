# TTS boot: apply saved mode (background keeps Silero daemon warm).
$ErrorActionPreference = "SilentlyContinue"
. (Join-Path $PSScriptRoot "_jarvis-data-dir.ps1")
$Ctl = Join-Path $PSScriptRoot "tts-worker-ctl.ps1"
$DataDir = Get-JarvisDataDir
$mode = "ondemand"
$modeFile = Join-Path $DataDir "tts.mode"
$db = Join-Path $DataDir "app.db"

# Prefer settings DB (user choice in GUI); fall back to sidecar flag.
if (Test-Path -LiteralPath $db) {
    try {
        $json = Get-Content -LiteralPath $db -Raw -Encoding UTF8 | ConvertFrom-Json
        if (("" + $json.tts_mode).Trim().ToLowerInvariant() -eq "background") { $mode = "background" }
    } catch {}
}
if ($mode -eq "ondemand" -and (Test-Path -LiteralPath $modeFile)) {
    try {
        $m = (Get-Content -LiteralPath $modeFile -Raw -Encoding UTF8).Trim().ToLowerInvariant()
        if ($m -eq "background") { $mode = "background" }
    } catch {}
}

try { Set-Content -LiteralPath $modeFile -Value $mode -Encoding ASCII } catch {}

if (Test-Path -LiteralPath $Ctl) {
    if ($mode -eq "background") {
        & $Ctl -Action start
    } else {
        & $Ctl -Action stop
    }
}
exit 0
