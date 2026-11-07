# Resolve install folder to a path that is safe for cmd.exe + PowerShell + same-tree checks.
# Prefer DOS 8.3 (ASCII) when available; otherwise emit the real Unicode long path as UTF-8.
param(
    [Parameter(Mandatory = $true)]
    [string]$AppDir,
    [Parameter(Mandatory = $true)]
    [string]$OutFile
)

$ErrorActionPreference = "Stop"
$AppDir = [IO.Path]::GetFullPath($AppDir).TrimEnd('\')

function Test-Ascii([string]$Path) {
    return ($Path -match '^[\x00-\x7F]+$')
}

$resolved = $AppDir
try {
    $fso = New-Object -ComObject Scripting.FileSystemObject
    $short = $fso.GetFolder($AppDir).ShortPath.TrimEnd('\')
    if ($short -and (Test-Path -LiteralPath (Join-Path $short "jarvis-app.exe")) -and (Test-Ascii $short)) {
        $resolved = $short
    }
} catch {}

# Always write UTF-8 without BOM so `set /p` in cmd does not see a BOM character.
$utf8 = New-Object System.Text.UTF8Encoding $false
[IO.File]::WriteAllText($OutFile, $resolved, $utf8)
Write-Output $resolved
exit 0
