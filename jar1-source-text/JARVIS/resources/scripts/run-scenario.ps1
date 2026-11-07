param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$ScenarioId
)

$ErrorActionPreference = "Stop"
$ScenarioId = $ScenarioId.Trim()

. (Join-Path $PSScriptRoot "_jarvis-data-dir.ps1")
. (Join-Path $PSScriptRoot "_jarvis-scenario.ps1")

$dbDir = Get-JarvisDataDir
$scenariosPath = Join-Path $dbDir "scenarios.json"

if (-not (Test-Path -LiteralPath $scenariosPath)) {
    throw "Scenarios file not found: $scenariosPath"
}

$bytes = [IO.File]::ReadAllBytes($scenariosPath)
if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    $json = [Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
} else {
    $json = [Text.Encoding]::UTF8.GetString($bytes)
}

$data = $json | ConvertFrom-Json
$all = @($data.scenarios)
$scenario = $all | Where-Object { [string]$_.id -eq $ScenarioId } | Select-Object -First 1

if (-not $scenario) {
    throw "Scenario not found: $ScenarioId (have $($all.Count) scenarios)"
}

$actions = @()
if ($null -ne $scenario.actions) {
    $actions = @($scenario.actions)
}
if ($actions.Count -eq 0 -and $scenario.target) {
    $actions = @(
        [pscustomobject]@{
            kind = $scenario.kind
            target = $scenario.target
        }
    )
}

if ($actions.Count -eq 0) {
    throw "Scenario contains no actions: $ScenarioId"
}

if (Invoke-JarvisScenario -Actions $actions) { exit 0 } else { exit 1 }
