# ASCII wrapper -> bundled Python schedule-job.py (no Cyrillic in this file)
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("schedule", "cancel_all", "cancel_one", "list", "list_json")]
    [string]$Action,
    [string]$Phrase = "",
    [string]$PhraseFile = "",
    [string]$Id = "",
    [ValidateSet("timer", "reminder", "auto")]
    [string]$Kind = "auto"
)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$pyScript = Join-Path $here "schedule-job.py"
$py = Join-Path $here "..\tts\runtime\python\python.exe"
if (-not (Test-Path -LiteralPath $py)) { $py = "python" }

if ($Action -eq "cancel_one") {
    . (Join-Path $here "_jarvis-data-dir.ps1")
    $StorePath = Join-Path (Get-JarvisDataDir) "reminders.json"
    if (-not (Test-Path -LiteralPath $StorePath)) { Write-Output "ERR:missing"; exit 2 }
    $obj = Get-Content -LiteralPath $StorePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $hit = $false
    $items = @()
    if ($null -ne $obj.items) {
        if ($obj.items -is [System.Array]) { $items = @($obj.items) } else { $items = @($obj.items) }
    }
    foreach ($it in $items) {
        if ("$($it.id)" -eq $Id -and -not $it.fired) { $it.fired = $true; $hit = $true }
    }
    $obj.items = $items
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [IO.File]::WriteAllText($StorePath, (($obj | ConvertTo-Json -Depth 8) + "`n"), $utf8)
    if ($hit) { Write-Output "CANCELLED:1"; exit 0 }
    Write-Output "ERR:not_found"
    exit 2
}

$argv = @($pyScript)
if ($Action -eq "cancel_all") { $argv += "cancel_all" }
elseif ($Action -eq "list") { $argv += "list" }
elseif ($Action -eq "list_json") { $argv += "list_json" }
else {
    $argv += @("schedule", "--kind", $Kind)
    if ($PhraseFile) {
        $argv += @("--phrase-file", $PhraseFile)
    }
    elseif ($Phrase) {
        $tmp = Join-Path $env:TEMP ("jarvis-sched-" + [guid]::NewGuid().ToString("N") + ".txt")
        [IO.File]::WriteAllText($tmp, $Phrase, [Text.UTF8Encoding]::new($false))
        $argv += @("--phrase-file", $tmp)
    }
}

$env:PYTHONIOENCODING = "utf-8"
& $py @argv
exit $LASTEXITCODE
