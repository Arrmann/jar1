param(
    [Parameter(Mandatory = $true, Position = 0)]
    [int]$Percent
)

$ErrorActionPreference = "Stop"
if ($Percent -lt 0) { $Percent = 0 }
if ($Percent -gt 100) { $Percent = 100 }

. (Join-Path $PSScriptRoot "audio-core.ps1")

try {
    $got = [JarvisCoreAudio.Volume]::SetScalar([float]($Percent / 100.0))
    Write-Host ("JARVIS volume set to {0}% (device reports {1:N0}%)" -f $Percent, ($got * 100))
    exit 0
} catch {
    Write-Warning "Core Audio unavailable ($($_.Exception.Message)); using keybd_event fallback"
    [JarvisCoreAudio.Volume]::SetScalarByKeys($Percent)
    Write-Host "JARVIS volume fallback approx $Percent%"
    exit 0
}
