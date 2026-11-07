param(
    [ValidateSet("TIMER", "REMINDER")]
    [string]$Kind = "TIMER"
)

# ASCII-only. Plays timer alarm then voice line at assistant_volume.
$ErrorActionPreference = "Continue"

. (Join-Path $PSScriptRoot "_jarvis-data-dir.ps1")

function Get-JarvisAssistantVolume {
    $vol = 1.0
    try {
        $db = Join-Path (Get-JarvisDataDir) "app.db"
        if (-not (Test-Path -LiteralPath $db)) { return $vol }
        $json = Get-Content -LiteralPath $db -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -ne $json.assistant_volume -and "$($json.assistant_volume)" -ne "") {
            $pct = [double]$json.assistant_volume
            if ($pct -lt 0) { $pct = 0 }
            if ($pct -gt 100) { $pct = 100 }
            $vol = $pct / 100.0
        }
    } catch {}
    return $vol
}

function Play-JarvisMp3([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return }
    if (-not (Test-Path -LiteralPath $path)) { return }
    $vol = Get-JarvisAssistantVolume
    try {
        Add-Type -AssemblyName PresentationCore -ErrorAction Stop
        $mp = New-Object System.Windows.Media.MediaPlayer
        $mp.Volume = $vol
        $uri = New-Object System.Uri ((Resolve-Path -LiteralPath $path).Path)
        $mp.Open($uri)
        $opened = $false
        $deadline = (Get-Date).AddSeconds(4)
        while ((Get-Date) -lt $deadline) {
            if ($mp.NaturalDuration.HasTimeSpan) { $opened = $true; break }
            Start-Sleep -Milliseconds 30
        }
        $durMs = if ($opened) {
            [Math]::Max(200, [int]($mp.NaturalDuration.TimeSpan.TotalMilliseconds + 150))
        } else {
            2500
        }
        $mp.Play()
        Start-Sleep -Milliseconds $durMs
        try { $mp.Stop() } catch {}
        try { $mp.Close() } catch {}
        return
    } catch {}
    try {
        $player = New-Object System.Media.SoundPlayer $path
        $player.PlaySync()
    } catch {
        try { [System.Media.SystemSounds]::Asterisk.Play() } catch {}
    }
}

$soundRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\sound"))
$alarmPath = Join-Path $soundRoot "timer-alarm.mp3"
# Spoken content is queued by the engine using the selected character.
# The HUD must never play a separate hard-coded voice over it.
if ($Kind -eq "TIMER") {
    Play-JarvisMp3 $alarmPath
}
exit 0