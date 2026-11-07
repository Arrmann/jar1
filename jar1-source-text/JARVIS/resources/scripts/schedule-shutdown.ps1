# ASCII wrapper -> Python schedule-job.py
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("schedule", "cancel", "status")]
    [string]$Action,
    [int]$Seconds = 0,
    [string]$Phrase = "",
    [string]$PhraseFile = ""
)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$py = Join-Path $here "..\tts\runtime\python\python.exe"
if (-not (Test-Path -LiteralPath $py)) { $py = "python" }
$script = Join-Path $here "schedule-job.py"
$env:PYTHONIOENCODING = "utf-8"

if ($Action -eq "cancel" -or $Action -eq "status") {
    & $py $script shutdown_cancel
    exit $LASTEXITCODE
}

$argv = @($script, "shutdown")
if ($Seconds -gt 0) {
    $argv += @("--seconds", "$Seconds")
}
elseif ($PhraseFile) {
    $argv += @("--phrase-file", $PhraseFile)
}
elseif ($Phrase) {
    $tmp = Join-Path $env:TEMP ("jarvis-shutdown-" + [guid]::NewGuid().ToString("N") + ".txt")
    [IO.File]::WriteAllText($tmp, $Phrase, [Text.UTF8Encoding]::new($false))
    $argv += @("--phrase-file", $tmp)
}
else {
    Write-Output "ERR:need_time"
    exit 2
}

& $py @argv
exit $LASTEXITCODE
