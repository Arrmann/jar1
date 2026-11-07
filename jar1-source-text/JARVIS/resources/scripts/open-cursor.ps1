# Launch Cursor GUI without a flashing cmd window.
# PATH "cursor" is usually cursor.cmd — Start-Process that shows a black console.
param()

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_jarvis-last-target.ps1")
Initialize-JarvisLastTarget
Invoke-JarvisPrepareOpen

function Find-GuiExe([string[]]$Names, [string[]]$ExtraPaths) {
    foreach ($p in $ExtraPaths) {
        if ($p -and (Test-Path -LiteralPath $p)) { return $p }
    }
    foreach ($name in $Names) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd -and $cmd.Source -and ($cmd.Source -like "*.exe") -and ($cmd.Source -notlike "*.cmd") -and ($cmd.Source -notlike "*.bat")) {
            return $cmd.Source
        }
    }
    return $null
}

$local = [string]$env:LOCALAPPDATA
$pf = [string]$env:ProgramFiles
$pf86 = [string]${env:ProgramFiles(x86)}

$cursor = Find-GuiExe @("Cursor.exe") @(
    (Join-Path $local "Programs\cursor\Cursor.exe"),
    (Join-Path $local "cursor\Cursor.exe"),
    (Join-Path $pf "Cursor\Cursor.exe"),
    (Join-Path $pf86 "Cursor\Cursor.exe")
)

if ($cursor) {
    Start-Process -FilePath $cursor | Out-Null
    . (Join-Path $PSScriptRoot "_jarvis-last-target.ps1")
    Register-JarvisOpenedApp -ProcessNames @("Cursor")
    exit 0
}

$code = Find-GuiExe @("Code.exe") @(
    (Join-Path $local "Programs\Microsoft VS Code\Code.exe"),
    (Join-Path $pf "Microsoft VS Code\Code.exe")
)

if ($code) {
    Start-Process -FilePath $code | Out-Null
    . (Join-Path $PSScriptRoot "_jarvis-last-target.ps1")
    Register-JarvisOpenedApp -ProcessNames @("Code")
    exit 0
}

$openUrl = Join-Path $PSScriptRoot "open-url.ps1"
if (Test-Path -LiteralPath $openUrl) {
    & $openUrl "https://cursor.com"
    exit $LASTEXITCODE
}
Write-Error "open-url.ps1 is missing; refusing to bypass the selected browser"
exit 1
