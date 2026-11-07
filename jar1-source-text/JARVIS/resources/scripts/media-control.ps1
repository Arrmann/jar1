param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet("play_pause", "next", "prev", "stop", "focus")]
    [string]$Action
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_jarvis-last-target.ps1")
Initialize-JarvisLastTarget

$focused = Get-JarvisMediaFocus
if ($Action -eq "focus") { if ($focused.Ok) { exit 0 } else { exit 1 } }
$sentInTab = $false
$kind = "generic"
if ($focused.Ok) {
    $hwnd = $focused.Hwnd
    $kind = "generic"
    if ($null -ne $focused.Kind -and "$($focused.Kind)".Length -gt 0) {
        $kind = ([string]$focused.Kind).ToLowerInvariant()
    } elseif ([bool]$focused.Youtube) {
        $kind = "youtube"
    }
    if ($kind -eq "generic") {
        $saved = Get-JarvisLastTarget
        $url = if ($null -ne $saved) { [string]$saved.url } else { "" }
        $kind = Get-JarvisMediaKind -Title ([string]$focused.Title) -Url $url -Proc ([string]$focused.Proc)
        if ($kind -eq "generic" -and ($url -match '(?i)vk\.(?:com|ru)|vkvideo')) { $kind = "vk" }
        if ($kind -eq "generic" -and ($url -match '(?i)youtube|youtu\.be')) { $kind = "youtube" }
    }

    # In-window hotkeys: YouTube K/Shift+N/P, Yandex L/H, VK Space/Ctrl+Arrows.
    if ($kind -eq "youtube" -or $kind -eq "yandex" -or $kind -eq "vk" -or $Action -eq "play_pause" -or $Action -eq "stop") {
        $sentInTab = Invoke-JarvisVkMedia -Hwnd $hwnd -Action $Action -Youtube ($kind -eq "youtube") -Kind $kind
    }
    if ($sentInTab) {
        Write-Host "JARVIS media-control: in-tab $Action kind=$kind title=$($focused.Title)"
    }
}

# System media keys only when in-tab path did not handle the action
# (avoids skipping two tracks). Covers Spotify / generic players / background SMTC.
if (-not $sentInTab) {
    if (-not ("JarvisMediaKeys" -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class JarvisMediaKeys {
  [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
  public const uint KEYEVENTF_KEYUP = 0x0002;
  public const byte VK_MEDIA_NEXT_TRACK = 0xB0;
  public const byte VK_MEDIA_PREV_TRACK = 0xB1;
  public const byte VK_MEDIA_STOP = 0xB2;
  public const byte VK_MEDIA_PLAY_PAUSE = 0xB3;
  public static void Tap(byte vk) {
    keybd_event(vk, 0, 0, UIntPtr.Zero);
    keybd_event(vk, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
  }
}
"@
    }
    switch ($Action) {
        "play_pause" { [JarvisMediaKeys]::Tap([JarvisMediaKeys]::VK_MEDIA_PLAY_PAUSE) }
        "next"       { [JarvisMediaKeys]::Tap([JarvisMediaKeys]::VK_MEDIA_NEXT_TRACK) }
        "prev"       { [JarvisMediaKeys]::Tap([JarvisMediaKeys]::VK_MEDIA_PREV_TRACK) }
        "stop"       { [JarvisMediaKeys]::Tap([JarvisMediaKeys]::VK_MEDIA_STOP) }
    }
    Write-Host "JARVIS media-control: system media key $Action (kind=$kind)"
}

exit 0
