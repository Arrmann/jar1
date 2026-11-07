# Exit 0 if every running jarvis-app / jarvis-gui lives under ExpectedDir.
# Exit 1 if any process is missing from ExpectedDir (wrong tree or absent).
param(
    [Parameter(Mandatory = $true)]
    [string]$ExpectedDir,
    [ValidateSet("app", "gui", "both")]
    [string]$Check = "both"
)

$ErrorActionPreference = "SilentlyContinue"

function Resolve-Long([string]$p) {
    if (-not $p) { return $null }
    try {
        if (Test-Path -LiteralPath $p) {
            return (Get-Item -LiteralPath $p).FullName.TrimEnd('\')
        }
    } catch {}
    try {
        return [System.IO.Path]::GetFullPath($p).TrimEnd('\')
    } catch {
        return $p.TrimEnd('\')
    }
}

function Paths-Equal([string]$a, [string]$b) {
    if (-not $a -or -not $b) { return $false }
    if ($a -ieq $b) { return $true }
    # 8.3 short vs long Unicode (Cyrillic installs / old launchers)
    try {
        $fso = New-Object -ComObject Scripting.FileSystemObject
        $sa = $fso.GetFolder($a).ShortPath.TrimEnd('\')
        $sb = $fso.GetFolder($b).ShortPath.TrimEnd('\')
        if ($sa -and $sb -and ($sa -ieq $sb)) { return $true }
    } catch {}
    return $false
}

function Process-Dir([string]$name) {
    $dirs = @()
    Get-CimInstance Win32_Process -Filter "Name='$name.exe'" -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.ExecutablePath) {
            $dirs += (Resolve-Long ([System.IO.Path]::GetDirectoryName($_.ExecutablePath)))
        }
    }
    return @($dirs | Where-Object { $_ } | Select-Object -Unique)
}

$want = Resolve-Long $ExpectedDir
if (-not $want) { exit 1 }

$needApp = ($Check -eq "app" -or $Check -eq "both")
$needGui = ($Check -eq "gui" -or $Check -eq "both")

if ($needApp) {
    $appDirs = @()
    foreach ($n in @("jarvis-app", "jarvis-run")) {
        $appDirs += Process-Dir $n
    }
    $appDirs = @($appDirs | Where-Object { $_ } | Select-Object -Unique)
    if ($appDirs.Count -eq 0) { exit 1 }
    foreach ($d in $appDirs) {
        if (-not (Paths-Equal $d $want)) { exit 1 }
    }
}

if ($needGui) {
    $guiDirs = Process-Dir "jarvis-gui"
    if ($guiDirs.Count -eq 0) { exit 1 }
    foreach ($d in $guiDirs) {
        if (-not (Paths-Equal $d $want)) { exit 1 }
    }
}

exit 0
