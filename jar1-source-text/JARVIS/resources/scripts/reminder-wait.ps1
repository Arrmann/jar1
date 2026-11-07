param(
    [Parameter(Mandatory = $true)]
    [string]$Id
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_jarvis-data-dir.ps1")
. (Join-Path $PSScriptRoot "_jarvis-hidden-process.ps1")
$StorePath = (Join-Path (Get-JarvisDataDir) "reminders.json")
$Hud = Join-Path $PSScriptRoot "reminder-hud.ps1"

function Read-Store {
    if (-not (Test-Path $StorePath)) { return $null }
    $raw = [IO.File]::ReadAllBytes($StorePath)
    if ($raw.Length -ge 3 -and $raw[0] -eq 0xEF -and $raw[1] -eq 0xBB -and $raw[2] -eq 0xBF) {
        $raw = $raw[3..($raw.Length - 1)]
    }
    return ([Text.Encoding]::UTF8.GetString($raw) | ConvertFrom-Json)
}

function Write-Store($store) {
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [IO.File]::WriteAllText($StorePath, (($store | ConvertTo-Json -Depth 6) + "`n"), $utf8)
}

# Wait until due or cancelled
while ($true) {
    $store = Read-Store
    if ($null -eq $store) { exit 0 }
    $item = @($store.items | Where-Object { $_.id -eq $Id } | Select-Object -First 1)
    if ($null -eq $item) { exit 0 }
    if ($item.fired) { exit 0 }

    $now = [int64]([DateTime]::UtcNow - [datetime]'1970-01-01').TotalSeconds
    if ([int64]$item.due_unix -le $now) { break }
    $sleep = [Math]::Min(1000, [Math]::Max(200, (([int64]$item.due_unix - $now) * 1000)))
    Start-Sleep -Milliseconds $sleep
}

$store = Read-Store
$item = @($store.items | Where-Object { $_.id -eq $Id } | Select-Object -First 1)
if ($null -eq $item -or $item.fired) { exit 0 }

# mark fired before showing (avoid double with Rust watcher)
foreach ($it in $store.items) {
    if ($it.id -eq $Id) { $it.fired = $true }
}
Write-Store $store

$tmp = Join-Path $env:TEMP ("jarvis-reminder-" + $Id + ".txt")
[IO.File]::WriteAllText($tmp, [string]$item.text, [Text.UTF8Encoding]::new($false))
$kind = if ($item.kind -eq "timer") { "TIMER" } else { "REMINDER" }
Start-JarvisHiddenProcess -FilePath "powershell.exe" -ArgumentList @(
    "-NoProfile", "-STA", "-ExecutionPolicy", "Bypass",
    "-File", $Hud, "-TextFile", $tmp, "-Kind", $kind
) | Out-Null
exit 0