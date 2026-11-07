param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet(
        "new_tab", "close_tab", "reopen_tab", "next_tab", "prev_tab",
        "refresh", "downloads", "history", "bookmark", "focus_address",
        "find", "zoom_in", "zoom_out", "fullscreen", "video_fullscreen", "escape",
        "back", "forward", "incognito"
    )]
    [string]$Action
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_jarvis-last-target.ps1")
Initialize-JarvisLastTarget

$needTab = $Action -in @(
    "refresh", "back", "forward", "zoom_in", "zoom_out",
    "find", "video_fullscreen", "fullscreen", "escape", "bookmark", "focus_address"
)
# close_tab / next / prev / new do NOT need keyword tab hunt - just FG browser + keys.
$focused = Invoke-JarvisFocusLastTab -NeedSpecificTab:$needTab
if (-not $focused.Ok) {
    Write-Host "JARVIS browser-control: abort (browser not foreground, refusing keys)"
    exit 2
}

# Tiny settle only when we had to steal focus; skip when already FG.
if (-not $focused.Matched -and $Action -notin @("close_tab", "next_tab", "prev_tab", "new_tab", "reopen_tab")) {
    Start-Sleep -Milliseconds 15
}

switch ($Action) {
    "new_tab"       { [JarvisLastTarget]::ChordFast([JarvisLastTarget]::VK_CONTROL, [JarvisLastTarget]::VK_T) }
    "close_tab" {
        # Only Ctrl+W. A Ctrl+F4 "retry" after a short sleep closed a second tab:
        # Chromium often keeps the same window title for >18ms after the first close.
        [JarvisLastTarget]::ChordFast([JarvisLastTarget]::VK_CONTROL, [JarvisLastTarget]::VK_W)
    }
    "reopen_tab"    { [JarvisLastTarget]::ChordFast([JarvisLastTarget]::VK_CONTROL, [JarvisLastTarget]::VK_SHIFT, [JarvisLastTarget]::VK_T) }
    "next_tab"      { [JarvisLastTarget]::ChordFast([JarvisLastTarget]::VK_CONTROL, [JarvisLastTarget]::VK_TAB) }
    "prev_tab"      { [JarvisLastTarget]::ChordFast([JarvisLastTarget]::VK_CONTROL, [JarvisLastTarget]::VK_SHIFT, [JarvisLastTarget]::VK_TAB) }
    "refresh"       { [JarvisLastTarget]::Tap([JarvisLastTarget]::VK_F5) }
    "downloads"     { [JarvisLastTarget]::Chord([JarvisLastTarget]::VK_CONTROL, [JarvisLastTarget]::VK_J) }
    "history"       { [JarvisLastTarget]::Chord([JarvisLastTarget]::VK_CONTROL, [JarvisLastTarget]::VK_H) }
    "bookmark"      { [JarvisLastTarget]::Chord([JarvisLastTarget]::VK_CONTROL, [JarvisLastTarget]::VK_D) }
    "focus_address" { [JarvisLastTarget]::Chord([JarvisLastTarget]::VK_CONTROL, [JarvisLastTarget]::VK_L) }
    "find"          { [JarvisLastTarget]::Chord([JarvisLastTarget]::VK_CONTROL, [JarvisLastTarget]::VK_F) }
    "zoom_in"       { [JarvisLastTarget]::Chord([JarvisLastTarget]::VK_CONTROL, [JarvisLastTarget]::VK_OEM_PLUS) }
    "zoom_out"      { [JarvisLastTarget]::Chord([JarvisLastTarget]::VK_CONTROL, [JarvisLastTarget]::VK_OEM_MINUS) }
    "fullscreen"    { [JarvisLastTarget]::Tap([JarvisLastTarget]::VK_F11) }
    "escape"        { [JarvisLastTarget]::Tap([JarvisLastTarget]::VK_ESCAPE) }
    "video_fullscreen" {
        $t = [string]$focused.Title
        $yt = [bool]$focused.Youtube -or ($t -match "(?i)youtube|youtu\.be")
        if (-not $yt) {
            $ru = ([string]([char]0x044E) + [char]0x0442 + [char]0x0443 + [char]0x0431)
            $yt = $t -match [regex]::Escape($ru)
        }
        if (-not $yt) {
            Write-Host "JARVIS browser-control: not a YouTube tab, skip video fullscreen"
            exit 3
        }
        # Same hardened path as maximize_video voice command.
        $script = Join-Path $PSScriptRoot "window-size.ps1"
        & powershell -NoProfile -ExecutionPolicy Bypass -File $script video
        exit $LASTEXITCODE
    }
    "back"          { [JarvisLastTarget]::Chord([JarvisLastTarget]::VK_MENU, [JarvisLastTarget]::VK_LEFT) }
    "forward"       { [JarvisLastTarget]::Chord([JarvisLastTarget]::VK_MENU, [JarvisLastTarget]::VK_RIGHT) }
    "incognito"     { [JarvisLastTarget]::Chord([JarvisLastTarget]::VK_CONTROL, [JarvisLastTarget]::VK_SHIFT, [JarvisLastTarget]::VK_N) }
}

if ($Action -eq "close_tab") {
    $hwnd = [IntPtr]$focused.Hwnd
    if ($hwnd -ne [IntPtr]::Zero -and [JarvisLastTarget]::IsWindow($hwnd) -and [JarvisLastTarget]::IsBrowserHwnd($hwnd)) {
        $title = [JarvisLastTarget]::TitleOf($hwnd)
        $proc = [JarvisLastTarget]::ProcName($hwnd)
        Save-JarvisLastTarget -Hwnd $hwnd -Process $proc -Title $title -Url "" -Keywords @() -Kind "browser"
    } else {
        $path = Get-JarvisLastTargetPath
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
    }
}

Write-Host "JARVIS browser-control: $Action done"
exit 0
