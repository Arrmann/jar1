# Scenario engine shared by generated runners (custom pack) and run-scenario.ps1.
# Windowed steps launch back-to-back; each window is snapped into its slot as soon
# as it appears, so slow apps never hold up the rest of the chain.
# ASCII-only: Windows PowerShell 5.1.

$geomHelper = Join-Path $PSScriptRoot "_jarvis-window-geom.ps1"
if (Test-Path -LiteralPath $geomHelper) { . $geomHelper }

function Test-JarvisWindowedKind([string]$k) {
    $k = $k.ToLowerInvariant()
    return ($k -eq "url" -or $k -eq "search" -or $k -eq "app" -or $k -eq "file" -or $k -eq "folder")
}

function Test-JarvisBrowserKind([string]$k) {
    $k = $k.ToLowerInvariant()
    return ($k -eq "url" -or $k -eq "search")
}

function ConvertTo-JarvisScenarioStep($Action) {
    $kind = ([string]$Action.kind).Trim().ToLowerInvariant()
    $target = ([string]$Action.target).Trim()
    $windowed = (Test-JarvisWindowedKind $kind) -and $target.Length -gt 0
    $mode = "none"
    $x = 0; $y = 0; $w = 0; $h = 0
    if ($windowed) {
        $mode = "auto"
        $win = $Action.win
        if ($null -ne $win -and $null -ne $win.mode) {
            $mode = ([string]$win.mode).Trim().ToLowerInvariant()
            try { $x = [int]$win.x; $y = [int]$win.y; $w = [int]$win.w; $h = [int]$win.h } catch {}
        }
        if ($mode -eq "" -or $mode -eq "tile" -or $mode -eq "grid") { $mode = "auto" }
        if ($mode -eq "region" -or $mode -eq "manual") { $mode = "custom" }
        if ($mode -eq "maximize" -or $mode -eq "fullscreen") { $mode = "max" }
        if ($mode -eq "off" -or $mode -eq "default") { $mode = "none" }
        if ($mode -eq "windows" -or $mode -eq "side") { $mode = "split" }
        if ($mode -eq "custom" -and ($w -lt 200 -or $h -lt 120)) { $mode = "auto" }
        if (@("auto", "custom", "max", "none", "split") -notcontains $mode) { $mode = "auto" }
    }
    return [pscustomobject]@{
        Kind = $kind; Target = $target; Windowed = $windowed; Mode = $mode
        X = $x; Y = $y; W = $w; H = $h
    }
}

function Clear-JarvisWinEnv {
    Remove-Item Env:JARVIS_TILE_COUNT,Env:JARVIS_TILE_INDEX,Env:JARVIS_WIN_X,Env:JARVIS_WIN_Y,Env:JARVIS_WIN_W,Env:JARVIS_WIN_H,Env:JARVIS_FORCE_NEW_WINDOW -ErrorAction SilentlyContinue
}

# Chromium --new-window + position (DIPs) only when we intentionally want a separate window.
function Set-JarvisBrowserRectEnv([int[]]$Rect) {
    $scale = [JarvisWinGeom]::ScaleAt($Rect[0] + [int]($Rect[2] / 2), $Rect[1] + [int]($Rect[3] / 2))
    $env:JARVIS_WIN_X = [string][int]($Rect[0] / $scale)
    $env:JARVIS_WIN_Y = [string][int]($Rect[1] / $scale)
    $env:JARVIS_WIN_W = [string][int]($Rect[2] / $scale)
    $env:JARVIS_WIN_H = [string][int]($Rect[3] / $scale)
    $env:JARVIS_FORCE_NEW_WINDOW = "1"
}

function Invoke-JarvisScenario {
    param([object[]]$Actions)

    $openTarget = Join-Path $PSScriptRoot "open-target.ps1"
    if (-not (Test-Path -LiteralPath $openTarget)) { throw "open-target.ps1 not found: $openTarget" }

    $steps = @(foreach ($a in @($Actions)) { if ($null -ne $a) { ConvertTo-JarvisScenarioStep $a } })
    # Links (url/search) in auto/none open as tabs in one browser window — not tiled.
    # Layout slots are for apps/files and for browser steps that explicitly want a window (max/custom/split).
    $placed = @($steps | Where-Object {
        $_.Windowed -and $_.Mode -ne "none" -and (
            -not (Test-JarvisBrowserKind $_.Kind) -or
            $_.Mode -eq "max" -or $_.Mode -eq "custom" -or $_.Mode -eq "split"
        )
    })
    $autoCount = @($placed | Where-Object { $_.Mode -eq "auto" -or $_.Mode -eq "split" }).Count

    $run = $null
    $wa = $null
    if ($placed.Count -gt 0 -and ("JarvisLayoutRun" -as [type])) {
        try {
            $run = [JarvisLayoutRun]::Start()
            $wa = [JarvisWinGeom]::WorkArea()
        } catch {
            Write-Warning "JARVIS layout disabled: $($_.Exception.Message)"
            $run = $null
        }
    }

    $env:JARVIS_PS_NESTED = "1"
    $env:JARVIS_SCENARIO_RUN = "1"
    $failed = $false
    $autoIndex = 0
    $order = 0
    try {
        foreach ($s in $steps) {
            $order++
            if ([string]::IsNullOrWhiteSpace($s.Kind) -or [string]::IsNullOrWhiteSpace($s.Target)) {
                $failed = $true
                continue
            }
            Clear-JarvisWinEnv

            $rect = $null
            $browserStep = Test-JarvisBrowserKind $s.Kind
            # url/search + auto → tabs (no --new-window). Opt-in separate windows: max / custom / split.
            $browserTabs = $browserStep -and ($s.Mode -eq "auto" -or $s.Mode -eq "none")
            $wantBrowserWindow = $browserStep -and -not $browserTabs -and $s.Mode -ne "none"
            if ($wantBrowserWindow) {
                # Even if layout helper failed, still force a new browser window for max/split.
                $env:JARVIS_FORCE_NEW_WINDOW = "1"
            }
            if ($run -and $s.Windowed -and $s.Mode -ne "none" -and -not $browserTabs) {
                if ($s.Mode -eq "auto" -or $s.Mode -eq "split") {
                    $rect = [JarvisWinGeom]::Layout($autoIndex, $autoCount, $wa)
                    $autoIndex++
                } elseif ($s.Mode -eq "custom") {
                    $rect = @($s.X, $s.Y, $s.W, $s.H, (10 + $order))
                } else {
                    # max — placeholder rect; layout engine maximizes the HWND
                    $rect = @(0, 0, 0, 0, (10 + $order))
                }
                if ($browserStep -and $null -ne $rect -and $rect[2] -ge 200 -and $rect[3] -ge 120) {
                    Set-JarvisBrowserRectEnv $rect
                }
            }

            $global:JARVIS_LAST_EXIT = 0
            try {
                & $openTarget $s.Kind $s.Target
                if ($null -ne $global:JARVIS_LAST_EXIT -and [int]$global:JARVIS_LAST_EXIT -ne 0) { $failed = $true }
            } catch {
                Write-Warning "Action failed kind=$($s.Kind) target=$($s.Target): $($_.Exception.Message)"
                $failed = $true
            }

            if ($null -ne $rect) {
                $m = Get-JarvisSlotMatch $s.Kind $s.Target
                [void]$run.AddSlot($m.Match, $m.Exes, ($s.Mode -eq "max"), $rect[0], $rect[1], $rect[2], $rect[3], $rect[4])
            }
        }
    } finally {
        Clear-JarvisWinEnv
        Remove-Item Env:JARVIS_PS_NESTED,Env:JARVIS_SCENARIO_RUN -ErrorAction SilentlyContinue
    }

    if ($run) {
        $run.Settle(16000, 900)
        try {
            $log = Join-Path $env:TEMP "jarvis-scenario-layout.log"
            (@("placed (ms since start, exe):") + @($run.Events)) | Set-Content -LiteralPath $log -Encoding UTF8
        } catch {}
    }
    return (-not $failed)
}
