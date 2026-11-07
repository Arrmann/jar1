param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Url,

    [Parameter(Mandatory = $false)]
    [ValidateSet("chrome", "yandex", "edge", "firefox", "opera", "brave", "default")]
    [string]$ForceBrowser = $null,

    # Optional explicit tile slot (0-based). Prefer env JARVIS_TILE_*.
    [int]$TileIndex = -1,
    [int]$TileCount = -1,

    # Test/diagnostic mode: resolve selected executable without launching it.
    [switch]$ResolveOnly
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_jarvis-data-dir.ps1")
. (Join-Path $PSScriptRoot "_jarvis-last-target.ps1")
Initialize-JarvisLastTarget
Invoke-JarvisPrepareOpen

function Complete-OpenUrl([int]$Code) {
    if ($Code -eq 0) {
        try {
            if ($env:JARVIS_SCENARIO_RUN -eq '1') {
                # The scenario layout engine tracks the window; keywords are enough for "close it".
                Save-JarvisLastTarget -Url $Url -Keywords @(Get-JarvisUrlKeywords $Url) -Kind "browser"
            } else {
                Register-JarvisOpenedUrl -Url $Url -Browser $browser
            }
        } catch {
            Write-Host "JARVIS open-url last-target failed: $($_.Exception.Message)"
        }
    }
    Set-Variable -Name JARVIS_LAST_EXIT -Scope Global -Value $Code
    if ($env:JARVIS_PS_NESTED -eq '1') {
        # Stop the rest of this script when invoked via `&` from a parent.
        throw "JARVIS_OPEN_URL_DONE:$Code"
    }
    exit $Code
}

function Get-JarvisDbPath {
    $p = Join-Path (Get-JarvisDataDir) "app.db"
    if (Test-Path -LiteralPath $p) { return $p }
    return $null
}

function Get-PreferredBrowser {
    $dbPath = Get-JarvisDbPath
    if (-not $dbPath) { return "chrome" }
    try {
        $raw = [IO.File]::ReadAllText($dbPath, [Text.Encoding]::UTF8)
        $db = $raw | ConvertFrom-Json
        if ($db.preferred_browser) { return ([string]$db.preferred_browser).ToLower().Trim() }
    } catch {}
    return "chrome"
}

function Find-BrowserExe([string]$Name) {
    $overrideName = "JARVIS_BROWSER_{0}_EXE" -f $Name.ToUpperInvariant()
    $override = [Environment]::GetEnvironmentVariable($overrideName)
    if ($override -and (Test-Path -LiteralPath $override -PathType Leaf)) {
        return (Resolve-Path -LiteralPath $override).Path
    }

    $pf = [Environment]::GetFolderPath("ProgramFiles")
    if ([string]::IsNullOrWhiteSpace($pf)) { $pf = [Environment]::GetEnvironmentVariable("ProgramFiles") }
    if ([string]::IsNullOrWhiteSpace($pf)) { $pf = "C:\Program Files" }
    $pf86 = ${env:ProgramFiles(x86)}
    if (-not $pf86) { $pf86 = [Environment]::GetEnvironmentVariable("ProgramFiles(x86)") }
    if ([string]::IsNullOrWhiteSpace($pf86)) { $pf86 = "C:\Program Files (x86)" }
    $local = [Environment]::GetFolderPath("LocalApplicationData")
    if ([string]::IsNullOrWhiteSpace($local)) {
        $local = Join-Path $env:USERPROFILE "AppData\Local"
    }

    $map = @{
        chrome = @(
            (Join-Path $pf "Google\Chrome\Application\chrome.exe"),
            (Join-Path $pf86 "Google\Chrome\Application\chrome.exe"),
            (Join-Path $local "Google\Chrome\Application\chrome.exe")
        )
        edge = @(
            (Join-Path $pf "Microsoft\Edge\Application\msedge.exe"),
            (Join-Path $pf86 "Microsoft\Edge\Application\msedge.exe")
        )
        firefox = @(
            (Join-Path $pf "Mozilla Firefox\firefox.exe"),
            (Join-Path $pf86 "Mozilla Firefox\firefox.exe")
        )
        opera = @(
            (Join-Path $local "Programs\Opera\opera.exe"),
            (Join-Path $local "Programs\Opera\launcher.exe"),
            (Join-Path $local "Programs\Opera GX\opera.exe"),
            (Join-Path $local "Programs\Opera GX\launcher.exe"),
            (Join-Path $pf "Opera\opera.exe"),
            (Join-Path $pf "Opera\launcher.exe"),
            (Join-Path $pf86 "Opera\opera.exe"),
            (Join-Path $pf86 "Opera\launcher.exe")
        )
        brave = @(
            (Join-Path $local "BraveSoftware\Brave-Browser\Application\brave.exe"),
            (Join-Path $pf "BraveSoftware\Brave-Browser\Application\brave.exe")
        )
        yandex = @(
            (Join-Path $local "Yandex\YandexBrowser\Application\browser.exe"),
            (Join-Path $pf "Yandex\YandexBrowser\Application\browser.exe"),
            (Join-Path $pf86 "Yandex\YandexBrowser\Application\browser.exe"),
            (Join-Path $local "Yandex\YandexBrowser\Application\yandex.exe"),
            (Join-Path $pf "Yandex\YandexBrowser\Application\yandex.exe")
        )
    }

    if ($map.ContainsKey($Name)) {
        foreach ($p in $map[$Name]) {
            if ($p -and (Test-Path -LiteralPath $p)) { return $p }
        }
    }

    if ($Name -eq "opera") {
        # Opera also registers itself as a Start Menu internet client. This is
        # more reliable than fixed paths for per-user, GX, beta and developer builds.
        foreach ($clientRoot in @(
            "Registry::HKEY_CURRENT_USER\Software\Clients\StartMenuInternet",
            "Registry::HKEY_LOCAL_MACHINE\Software\Clients\StartMenuInternet"
        )) {
            try {
                foreach ($client in Get-ChildItem -LiteralPath $clientRoot -ErrorAction Stop) {
                    $displayName = [string](Get-ItemProperty -LiteralPath $client.PSPath -ErrorAction SilentlyContinue).'(default)'
                    if ($client.PSChildName -notlike "Opera*" -and $displayName -notlike "*Opera*") {
                        continue
                    }
                    $commandKey = Join-Path $client.PSPath "shell\open\command"
                    $command = [string](Get-ItemProperty -LiteralPath $commandKey -ErrorAction SilentlyContinue).'(default)'
                    $candidate = $null
                    if ($command -match '^\s*"([^"]+\.exe)"') {
                        $candidate = $Matches[1]
                    } elseif ($command -match '^\s*([^\s]+\.exe)') {
                        $candidate = $Matches[1]
                    }
                    if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
                        return $candidate
                    }
                }
            } catch {}
        }

        foreach ($uninstallRoot in @(
            "Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Uninstall",
            "Registry::HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\Uninstall",
            "Registry::HKEY_LOCAL_MACHINE\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
        )) {
            try {
                foreach ($key in Get-ChildItem -LiteralPath $uninstallRoot -ErrorAction Stop) {
                    $entry = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
                    if ($key.PSChildName -notlike "Opera*" -and ([string]$entry.DisplayName) -notlike "*Opera*") {
                        continue
                    }
                    $displayIconRaw = [string]$entry.DisplayIcon
                    $displayIcon = if ($displayIconRaw -match '^\s*"([^"]+\.exe)"') {
                        $Matches[1]
                    } else {
                        $displayIconRaw.Split(",")[0].Trim().Trim('"')
                    }
                    $candidates = @($displayIcon)
                    $installLocation = [string]$entry.InstallLocation
                    if ($installLocation) {
                        $candidates += (Join-Path $installLocation "opera.exe")
                        $candidates += (Join-Path $installLocation "launcher.exe")
                    }
                    foreach ($candidate in $candidates) {
                        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
                            return $candidate
                        }
                    }
                }
            } catch {}
        }
    }

    $appNames = @{
        chrome = @("chrome.exe")
        edge = @("msedge.exe")
        firefox = @("firefox.exe")
        opera = @("opera.exe")
        brave = @("brave.exe")
        yandex = @("browser.exe", "yandex.exe")
    }
    if ($appNames.ContainsKey($Name)) {
        foreach ($appName in $appNames[$Name]) {
            foreach ($root in @(
                "Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\App Paths",
                "Registry::HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\App Paths",
                "Registry::HKEY_LOCAL_MACHINE\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths"
            )) {
                try {
                    $registered = (Get-ItemProperty -LiteralPath (Join-Path $root $appName) -ErrorAction Stop).'(default)'
                    if ($registered -and (Test-Path -LiteralPath $registered -PathType Leaf)) {
                        return $registered
                    }
                } catch {}
            }
        }
    }

    $cmdNames = @{
        chrome = @("chrome", "chrome.exe")
        edge = @("msedge", "msedge.exe")
        firefox = @("firefox", "firefox.exe")
        opera = @("opera", "opera.exe")
        brave = @("brave", "brave.exe")
        yandex = @("browser", "browser.exe")
    }
    if ($cmdNames.ContainsKey($Name)) {
        foreach ($c in $cmdNames[$Name]) {
            $cmd = Get-Command $c -ErrorAction SilentlyContinue
            if ($cmd -and $cmd.Source) { return $cmd.Source }
        }
    }
    return $null
}

function Get-WorkArea {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue | Out-Null
    try {
        # Prefer the monitor under the mouse / foreground - not always PrimaryScreen.
        $pt = [System.Windows.Forms.Cursor]::Position
        $screen = [System.Windows.Forms.Screen]::FromPoint($pt)
        if ($null -eq $screen) { $screen = [System.Windows.Forms.Screen]::PrimaryScreen }
        $wa = $screen.WorkingArea
        return @{ X = [int]$wa.X; Y = [int]$wa.Y; W = [int]$wa.Width; H = [int]$wa.Height }
    } catch {
        return @{ X = 0; Y = 0; W = 1920; H = 1080 }
    }
}

function Get-TileRect([int]$index, [int]$count) {
    # Breathing room between windows; never full-bleed for multi-open.
    $margin = 28
    $gap = 18
    $wa = Get-WorkArea
    $innerW = [Math]::Max(400, $wa.W - (2 * $margin))
    $innerH = [Math]::Max(300, $wa.H - (2 * $margin))
    $n = [Math]::Max(1, [Math]::Min(6, $count))
    $i = [Math]::Max(0, [Math]::Min($n - 1, $index))

    switch ($n) {
        1 { $cols = 1; $rows = 1 }
        2 { $cols = 2; $rows = 1 }
        3 { $cols = 3; $rows = 1 }
        4 { $cols = 2; $rows = 2 }
        5 { $cols = 3; $rows = 2 }
        default { $cols = 3; $rows = 2 }
    }

    $cellW = [int](($innerW - (($cols - 1) * $gap)) / $cols)
    $cellH = [int](($innerH - (($rows - 1) * $gap)) / $rows)
    # Keep windows substantial but with air (~82-92% of cell).
    $winW = [int]($cellW * 0.92)
    $winH = [int]($cellH * 0.90)

    if ($n -eq 5 -and $i -ge 3) {
        # Bottom row: two centered cells under a 3-col top.
        $bottomCols = 2
        $bi = $i - 3
        $bCellW = [int](($innerW - (($bottomCols - 1) * $gap)) / $bottomCols)
        $winW = [int]($bCellW * 0.92)
        $row = 1
        $col = $bi
        $padX = [int](($innerW - (($bottomCols * $bCellW) + (($bottomCols - 1) * $gap))) / 2)
        $x = $wa.X + $margin + $padX + ($col * ($bCellW + $gap)) + [int](($bCellW - $winW) / 2)
        $y = $wa.Y + $margin + ($row * ($cellH + $gap)) + [int](($cellH - $winH) / 2)
        return @{ X = $x; Y = $y; W = $winW; H = $winH }
    }

    $col = $i % $cols
    $row = [int][Math]::Floor($i / $cols)
    $x = $wa.X + $margin + ($col * ($cellW + $gap)) + [int](($cellW - $winW) / 2)
    $y = $wa.Y + $margin + ($row * ($cellH + $gap)) + [int](($cellH - $winH) / 2)
    return @{ X = $x; Y = $y; W = $winW; H = $winH }
}

function Resolve-TileArgs {
    $ti = $TileIndex
    $tc = $TileCount
    if ($env:JARVIS_TILE_INDEX -match '^\d+$') { $ti = [int]$env:JARVIS_TILE_INDEX }
    if ($env:JARVIS_TILE_COUNT -match '^\d+$') { $tc = [int]$env:JARVIS_TILE_COUNT }
    # Explicit custom rect from constructor (screen pixels).
    if ($env:JARVIS_WIN_W -match '^\d+$' -and $env:JARVIS_WIN_H -match '^\d+$') {
        $ww = [int]$env:JARVIS_WIN_W
        $wh = [int]$env:JARVIS_WIN_H
        if ($ww -ge 200 -and $wh -ge 120) {
            $wx = 0; $wy = 0
            if ($env:JARVIS_WIN_X -match '^-?\d+$') { $wx = [int]$env:JARVIS_WIN_X }
            if ($env:JARVIS_WIN_Y -match '^-?\d+$') { $wy = [int]$env:JARVIS_WIN_Y }
            # Clamp into a real screen so a saved rect from another PC does not open off-desktop.
            try {
                Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue | Out-Null
                $screen = [System.Windows.Forms.Screen]::FromPoint((New-Object System.Drawing.Point($wx, $wy)))
                if ($null -eq $screen) { $screen = [System.Windows.Forms.Screen]::PrimaryScreen }
                $b = $screen.WorkingArea
                if ($wx -lt $b.Left - 40 -or $wx -gt ($b.Right - 80) -or $wy -lt $b.Top - 40 -or $wy -gt ($b.Bottom - 80)) {
                    $wx = $b.Left + 40
                    $wy = $b.Top + 40
                }
                if ($ww -gt $b.Width) { $ww = [Math]::Max(200, $b.Width - 80) }
                if ($wh -gt $b.Height) { $wh = [Math]::Max(120, $b.Height - 80) }
            } catch {}
            return @{ X = $wx; Y = $wy; W = $ww; H = $wh }
        }
    }
    if ($tc -lt 2) { return $null }
    if ($ti -lt 0) { $ti = 0 }
    return Get-TileRect -index $ti -count $tc
}

function Test-JarvisForceNewWindow {
    $v = [string]$env:JARVIS_FORCE_NEW_WINDOW
    return ($v -eq "1" -or $v -eq "true" -or $v -eq "yes")
}

function Build-ChromiumArgs([string]$url, $tile) {
    $args = New-Object System.Collections.Generic.List[string]
    # Separate window only when tiling / explicit force. Otherwise Chromium opens a tab
    # in the existing profile window (what users expect for multiple https links).
    $wantNew = ($null -ne $tile) -or (Test-JarvisForceNewWindow)
    if ($wantNew) {
        [void]$args.Add("--new-window")
        if ($null -ne $tile) {
            [void]$args.Add(("--window-position={0},{1}" -f $tile.X, $tile.Y))
            [void]$args.Add(("--window-size={0},{1}" -f $tile.W, $tile.H))
        }
    }
    [void]$args.Add($url)
    return , $args.ToArray()
}

$browser = Get-PreferredBrowser
if ($ForceBrowser) { $browser = $ForceBrowser.ToLowerInvariant() }
$tile = Resolve-TileArgs
Write-Host "JARVIS open-url browser=$browser url=$Url tile=$(if($tile){"$($tile.X),$($tile.Y) $($tile.W)x$($tile.H)"}else{'none'})"

if ($ResolveOnly) {
    if ($browser -eq "default") {
        Write-Output "RESOLVED|default|system"
        exit 0
    }
    $resolvedExe = Find-BrowserExe $browser
    if ($resolvedExe) {
        Write-Output "RESOLVED|$browser|$resolvedExe"
        exit 0
    }
    Write-Output "MISSING|$browser"
    exit 2
}

if ($browser -ne "default") {
    $exe = Find-BrowserExe $browser
    if ($exe) {
        Write-Host "JARVIS open-url exe=$exe"
        # Complete-OpenUrl throws when nested - keep it outside try/catch.
        $launched = $false
        try {
            $argList = Build-ChromiumArgs -url $Url -tile $tile
            # Firefox: -new-window only when we intentionally want a separate window.
            if ($browser -eq "firefox") {
                $wantNew = ($null -ne $tile) -or (Test-JarvisForceNewWindow)
                if ($wantNew) {
                    $argList = @("-new-window", $Url)
                } else {
                    $argList = @("-new-tab", $Url)
                }
            }
            Start-Process -FilePath $exe -ArgumentList $argList -ErrorAction Stop | Out-Null
            Write-Host "JARVIS open-url launched preferred browser"
            $launched = $true
        } catch {
            Write-Host "JARVIS open-url Start-Process failed: $($_.Exception.Message)"
        }
        if ($launched) { Complete-OpenUrl 0 }
    } else {
        Write-Host "Browser '$browser' executable not found"
    }

    if ($browser -eq "edge") {
        $launched = $false
        try {
            Start-Process ("microsoft-edge:{0}" -f $Url) -ErrorAction Stop | Out-Null
            Write-Host "JARVIS open-url used microsoft-edge protocol"
            $launched = $true
        } catch {
            Write-Host "JARVIS open-url protocol fallback failed: $($_.Exception.Message)"
        }
        if ($launched) { Complete-OpenUrl 0 }
    }

    # Never betray an explicit choice by silently opening another browser.
    # The caller/UI can now report that the selected browser is unavailable.
    Write-Host "Selected browser '$browser' could not be launched; system fallback disabled"
    Complete-OpenUrl 2
}

$launched = $false
try {
    Start-Process $Url -ErrorAction Stop | Out-Null
    Write-Host "JARVIS open-url used system default"
    $launched = $true
} catch {
    Write-Host "JARVIS open-url default open failed: $($_.Exception.Message)"
}
if ($launched) { Complete-OpenUrl 0 } else { Complete-OpenUrl 1 }
