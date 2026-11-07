# Seed Start Menu shortcuts for installed Steam games so JARVIS app picker finds CS/etc.
# WScript cannot Save() .lnk into Start Menu under some Windows policies, so we:
# 1) build .lnk in a local cache folder
# 2) Copy-Item them into %APPDATA%\...\Start Menu\Programs\JARVIS Games
$ErrorActionPreference = "SilentlyContinue"

function Get-SteamRoots {
    $roots = New-Object System.Collections.Generic.List[string]
    foreach ($key in @(
        "HKCU:\Software\Valve\Steam",
        "HKLM:\Software\Valve\Steam",
        "HKLM:\Software\WOW6432Node\Valve\Steam"
    )) {
        try {
            $sp = (Get-ItemProperty -LiteralPath $key -ErrorAction Stop).SteamPath
            if ($sp) {
                $full = [IO.Path]::GetFullPath($sp)
                if (Test-Path -LiteralPath $full) { [void]$roots.Add($full) }
            }
        } catch {}
    }
    foreach ($p in @(
        "${env:ProgramFiles(x86)}\Steam",
        "$env:ProgramFiles\Steam",
        "$env:LOCALAPPDATA\Steam",
        "D:\Steam", "E:\Steam", "C:\Steam"
    )) {
        if ($p -and (Test-Path -LiteralPath $p)) {
            [void]$roots.Add([IO.Path]::GetFullPath($p))
        }
    }
    return @($roots | Select-Object -Unique)
}

function Get-SteamLibraries([string]$steamRoot) {
    $libs = New-Object System.Collections.Generic.List[string]
    [void]$libs.Add($steamRoot)
    $vdf = Join-Path $steamRoot "steamapps\libraryfolders.vdf"
    if (Test-Path -LiteralPath $vdf) {
        foreach ($line in [IO.File]::ReadAllLines($vdf)) {
            if ($line -match '"path"\s+"([^"]+)"') {
                $path = [IO.Path]::GetFullPath(($Matches[1] -replace '\\\\', '\'))
                if (Test-Path -LiteralPath $path) { [void]$libs.Add($path) }
            }
        }
    }
    return @($libs | Select-Object -Unique)
}

function Get-VdfValue([string]$content, [string]$key) {
    $pattern = '"' + [regex]::Escape($key) + '"\s+"([^"]*)"'
    $m = [regex]::Match($content, $pattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
}

function Test-NoiseGame([string]$name, [string]$appId) {
    if ($appId -eq "228980") { return $true }
    $n = $name.ToLowerInvariant()
    return ($n -match 'steamworks|redistributable|proton|steam linux runtime|dedicated server')
}

function New-SafeFileName([string]$name) {
    foreach ($ch in [IO.Path]::GetInvalidFileNameChars()) {
        $name = $name.Replace([string]$ch, " ")
    }
    $clean = ($name -replace '\s+', ' ').Trim()
    if ([string]::IsNullOrWhiteSpace($clean)) { $clean = "Steam Game" }
    if ($clean.Length -gt 80) { $clean = $clean.Substring(0, 80).Trim() }
    return $clean
}

function Write-SteamShortcut([string]$folder, [string]$displayName, [string]$steamExe, [string]$appId) {
    $lnkPath = Join-Path $folder ("{0}.lnk" -f (New-SafeFileName $displayName))
    $shell = New-Object -ComObject WScript.Shell
    $sc = $shell.CreateShortcut($lnkPath)
    $sc.TargetPath = $steamExe
    $sc.Arguments = "-applaunch $appId"
    $sc.WorkingDirectory = (Split-Path -Parent $steamExe)
    $sc.Description = "Steam app $appId - $displayName"
    $sc.Save()
    return $lnkPath
}

$steamRoots = @(Get-SteamRoots)
if ($steamRoots.Count -eq 0) {
    Write-Host "JARVIS: Steam not found - skip game catalog"
    exit 0
}

$cacheDir = Join-Path $env:TEMP "jarvis-steam-shortcuts"
$outDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\JARVIS Games"
New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

Get-ChildItem -LiteralPath $cacheDir -Filter "*.lnk" -ErrorAction SilentlyContinue |
    Remove-Item -Force -ErrorAction SilentlyContinue

$created = 0
$seenIds = @{}

foreach ($root in $steamRoots) {
    $steamExe = Join-Path $root "steam.exe"
    if (-not (Test-Path -LiteralPath $steamExe)) { continue }

    foreach ($lib in @(Get-SteamLibraries $root)) {
        $appsDir = Join-Path $lib "steamapps"
        if (-not (Test-Path -LiteralPath $appsDir)) { continue }

        $manifests = @()
        try { $manifests = @([IO.Directory]::GetFiles($appsDir, "appmanifest_*.acf")) } catch { $manifests = @() }
        if ($manifests.Count -eq 0) {
            $vdf = Join-Path $root "steamapps\libraryfolders.vdf"
            if (Test-Path -LiteralPath $vdf) {
                $vdfText = [IO.File]::ReadAllText($vdf)
                foreach ($m in [regex]::Matches($vdfText, '"(\d{3,})"\s+"\d+"')) {
                    $cand = Join-Path $appsDir ("appmanifest_{0}.acf" -f $m.Groups[1].Value)
                    if ([IO.File]::Exists($cand)) { $manifests += $cand }
                }
            }
        }

        foreach ($manifestPath in $manifests) {
            try {
                $raw = [IO.File]::ReadAllText($manifestPath)
                $appId = Get-VdfValue $raw "appid"
                $name = Get-VdfValue $raw "name"
                if ([string]::IsNullOrWhiteSpace($appId)) {
                    $base = [IO.Path]::GetFileNameWithoutExtension($manifestPath)
                    if ($base -match 'appmanifest_(\d+)') { $appId = $Matches[1] }
                }
                if ([string]::IsNullOrWhiteSpace($name)) { $name = "Steam App $appId" }
                if ([string]::IsNullOrWhiteSpace($appId)) { continue }
                if ($seenIds.ContainsKey($appId)) { continue }
                if (Test-NoiseGame $name $appId) { continue }

                $seenIds[$appId] = $true
                Write-SteamShortcut $cacheDir $name $steamExe $appId | Out-Null
                $created++

                if ($appId -eq "730") {
                    Write-SteamShortcut $cacheDir "CS2" $steamExe $appId | Out-Null
                    Write-SteamShortcut $cacheDir "CS" $steamExe $appId | Out-Null
                    Write-SteamShortcut $cacheDir "Counter-Strike" $steamExe $appId | Out-Null
                    $created += 3
                }
            } catch {}
        }
    }
}

# Publish into Start Menu (Copy-Item works where WScript.Save is blocked by policy).
Get-ChildItem -LiteralPath $outDir -Filter "*.lnk" -ErrorAction SilentlyContinue |
    Remove-Item -Force -ErrorAction SilentlyContinue
Copy-Item -Force (Join-Path $cacheDir "*.lnk") $outDir -ErrorAction SilentlyContinue

$published = @(Get-ChildItem -LiteralPath $outDir -Filter "*.lnk" -ErrorAction SilentlyContinue).Count
Write-Host "JARVIS: Steam game shortcuts refreshed (built=$created published=$published) -> $outDir"
exit 0
