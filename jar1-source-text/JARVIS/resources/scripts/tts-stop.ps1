# Stop ALL JARVIS TTS (Esc / "останови озвучку") — generate + play + queue.
# Must not restamp cancel flags or kill speak.py that started AFTER this Esc.
$ErrorActionPreference = "SilentlyContinue"
. (Join-Path $PSScriptRoot "_jarvis-data-dir.ps1")
$DataDir = Get-JarvisDataDir
$StopFile = Join-Path $DataDir "tts.stop"
$CancelFile = Join-Path $DataDir "tts.cancel"
$PidFile = Join-Path $DataDir "tts.pid"
$SpeakingFile = Join-Path $DataDir "tts.speaking"
$PlayJobFile = Join-Path $DataDir "tts.play.job"
$PlayDoneFile = Join-Path $DataDir "tts.play.done"
$PlayDaemonPidFile = Join-Path $DataDir "tts.play.daemon.pid"
$IssuedFile = Join-Path $DataDir "tts.stop.issued"
$GenFile = Join-Path $DataDir "tts.gen"

New-Item -ItemType Directory -Force -Path $DataDir | Out-Null

$issuedMs = [int64]0
if (Test-Path -LiteralPath $IssuedFile) {
    [void][int64]::TryParse(((Get-Content -LiteralPath $IssuedFile -Raw -ErrorAction SilentlyContinue).Trim()), [ref]$issuedMs)
}
if ($issuedMs -le 0) {
    $issuedMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
}

$genMs = [int64]0
if (Test-Path -LiteralPath $GenFile) {
    [void][int64]::TryParse(((Get-Content -LiteralPath $GenFile -Raw -ErrorAction SilentlyContinue).Trim()), [ref]$genMs)
}

# Next utterance already called clear_cancel() — do not poison it.
$newSpeakStarted = ($genMs -ge $issuedMs -and $genMs -gt 0)
if (-not $newSpeakStarted) {
    Set-Content -LiteralPath $CancelFile -Value "1" -Encoding ASCII
    Set-Content -LiteralPath $StopFile -Value "1" -Encoding ASCII
}

$cutoff = [DateTimeOffset]::FromUnixTimeMilliseconds($issuedMs).LocalDateTime.AddSeconds(1)

function Test-CreatedBeforeStop($proc) {
    if (-not $proc.CreationDate) {
        return $false
    }
    return $proc.CreationDate -lt $cutoff
}

foreach ($pf in @($PidFile, $PlayDaemonPidFile)) {
    if (Test-Path -LiteralPath $pf) {
        $raw = (Get-Content -LiteralPath $pf -Raw).Trim()
        $ttsPid = 0
        if ([int]::TryParse($raw, [ref]$ttsPid) -and $ttsPid -gt 0) {
            $proc = Get-Process -Id $ttsPid -ErrorAction SilentlyContinue
            if ($proc -and $proc.StartTime -lt $cutoff) {
                Stop-Process -Id $ttsPid -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

# Kill PowerShell hosts running tts-speak / leftover tts-stop (Windows PS + pwsh).
Get-CimInstance Win32_Process | Where-Object {
    $_.Name -match '^(powershell|pwsh)\.exe$' -and $_.CommandLine -and (
        $_.CommandLine -like "*tts-speak.ps1*" -or $_.CommandLine -like "*tts-stop.ps1*"
    ) -and $_.ProcessId -ne $PID -and (Test-CreatedBeforeStop $_)
} | ForEach-Object {
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
}

# Kill only on-demand speak.py that existed at Esc. NEVER kill tts_daemon.py or
# the resident `speak.py --serve` — Esc must leave the warm model alive or the
# next reply spends seconds reloading torch and feels broken.
Get-CimInstance Win32_Process | Where-Object {
    $_.Name -match '^(python|pythonw)\.exe$' -and $_.CommandLine -and (
        $_.CommandLine -like "*resources\tts\speak.py*" -or
        $_.CommandLine -like "*resources/tts/speak.py*" -or
        $_.CommandLine -like "*\tts\speak.py*" -or
        $_.CommandLine -like "*/tts/speak.py*" -or
        $_.CommandLine -like "*JARVIS\tts\speak.py*"
    ) -and ($_.CommandLine -notlike "*tts_daemon.py*") -and ($_.CommandLine -notlike "*--serve*") -and (Test-CreatedBeforeStop $_)
} | ForEach-Object {
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
}

Remove-Item -LiteralPath $SpeakingFile,$PidFile,$PlayJobFile,$PlayDoneFile,$PlayDaemonPidFile -Force -ErrorAction SilentlyContinue

# Esc flags stay so in-flight SpeakQueue / generate loops exit. Next speak
# writes tts.gen and clears them. Do not kill the warm tts_daemon.
exit 0
