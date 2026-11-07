param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Target,

    [string[]]$ProcessNames = @()
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_jarvis-last-target.ps1")
Initialize-JarvisLastTarget
Invoke-JarvisPrepareOpen

$Target = [Environment]::ExpandEnvironmentVariables("$Target").Trim().Trim('"')
if ([string]::IsNullOrWhiteSpace($Target)) {
    throw "Empty process target"
}

$leaf = [IO.Path]::GetFileNameWithoutExtension($Target)
if ($ProcessNames.Count -lt 1) {
    switch ($leaf.ToLowerInvariant()) {
        "calc"    { $ProcessNames = @("CalculatorApp", "ApplicationFrameHost", "Calculator", "calc") }
        "notepad" { $ProcessNames = @("notepad") }
        "mspaint" { $ProcessNames = @("mspaint") }
        default   { $ProcessNames = @($leaf) }
    }
}

Start-Process -FilePath $Target -ErrorAction Stop | Out-Null
Register-JarvisOpenedApp -ProcessNames $ProcessNames
Write-Host "JARVIS open-process: $Target"
exit 0
