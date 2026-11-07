param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet(
        "steam", "telegram", "epic", "obs", "emoji", "snip", "gamebar", "run",
        "chatgpt", "deepseek", "claude", "gemini"
    )]
    [string]$App
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_jarvis-last-target.ps1")
Initialize-JarvisLastTarget
Invoke-JarvisPrepareOpen

function Open-Url([string]$Url) {
    $script = Join-Path $PSScriptRoot "open-url.ps1"
    $env:JARVIS_PS_NESTED = "1"
    try {
        & $script $Url
    } catch {
        if ("$($_.Exception.Message)" -notmatch '^JARVIS_OPEN_URL_DONE:') { throw }
    }
    $code = 0
    if ($null -ne $global:JARVIS_LAST_EXIT) { $code = [int]$global:JARVIS_LAST_EXIT }
    exit $code
}

function Find-SteamExe {
    $candidates = New-Object System.Collections.Generic.List[string]
    foreach ($root in @("HKCU:\Software\Valve\Steam", "HKLM:\Software\Valve\Steam", "HKLM:\Software\WOW6432Node\Valve\Steam")) {
        try {
            $sp = (Get-ItemProperty -LiteralPath $root -ErrorAction Stop).SteamPath
            if ($sp) {
                $candidates.Add((Join-Path $sp "steam.exe"))
            }
        } catch {}
    }
    foreach ($p in @(
        (Join-Path $env:ProgramFiles "Steam\steam.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Steam\steam.exe"),
        (Join-Path $env:LOCALAPPDATA "Steam\steam.exe"),
        "D:\Steam\steam.exe",
        "E:\Steam\steam.exe",
        "C:\Steam\steam.exe"
    )) {
        if ($p) { $candidates.Add($p) }
    }

    # Start Menu shortcuts
    $startRoots = @(
        [IO.Path]::Combine($env:ProgramData, "Microsoft\Windows\Start Menu\Programs"),
        [IO.Path]::Combine($env:APPDATA, "Microsoft\Windows\Start Menu\Programs")
    )
    foreach ($root in $startRoots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        Get-ChildItem -LiteralPath $root -Recurse -Filter "*Steam*.lnk" -ErrorAction SilentlyContinue |
            Select-Object -First 8 |
            ForEach-Object {
                try {
                    $sh = New-Object -ComObject WScript.Shell
                    $target = $sh.CreateShortcut($_.FullName).TargetPath
                    if ($target) { $candidates.Add($target) }
                } catch {}
            }
    }

    foreach ($p in $candidates) {
        if ($p -and (Test-Path -LiteralPath $p)) { return $p }
    }
    return $null
}

function Find-TelegramExe {
    $candidates = New-Object System.Collections.Generic.List[string]
    foreach ($p in @(
        (Join-Path $env:APPDATA "Telegram Desktop\Telegram.exe"),
        (Join-Path $env:LOCALAPPDATA "Telegram Desktop\Telegram.exe"),
        (Join-Path $env:ProgramFiles "Telegram Desktop\Telegram.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Telegram Desktop\Telegram.exe")
    )) {
        if ($p) { $candidates.Add($p) }
    }

    $startRoots = @(
        [IO.Path]::Combine($env:ProgramData, "Microsoft\Windows\Start Menu\Programs"),
        [IO.Path]::Combine($env:APPDATA, "Microsoft\Windows\Start Menu\Programs")
    )
    foreach ($root in $startRoots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        Get-ChildItem -LiteralPath $root -Recurse -Filter "*Telegram*.lnk" -ErrorAction SilentlyContinue |
            Select-Object -First 8 |
            ForEach-Object {
                try {
                    $sh = New-Object -ComObject WScript.Shell
                    $target = $sh.CreateShortcut($_.FullName).TargetPath
                    if ($target -and ($target -like "*Telegram.exe")) { $candidates.Add($target) }
                } catch {}
            }
    }

    foreach ($p in $candidates) {
        if ($p -and (Test-Path -LiteralPath $p)) { return $p }
    }
    return $null
}

function Show-Missing([string]$Title, [string]$Body) {
    try {
        Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue
        [System.Windows.MessageBox]::Show($Body, $Title, "OK", "Warning") | Out-Null
    } catch {
        Write-Warning "$Title :: $Body"
    }
}

switch ($App) {
    "steam" {
        $exe = Find-SteamExe
        if ($exe) {
            Start-Process -FilePath $exe | Out-Null
            Register-JarvisOpenedApp -ProcessNames @("steam", "steamwebhelper")
            Write-Host "JARVIS opened Steam: $exe"
            exit 0
        }
        try {
            Start-Process "steam://" -ErrorAction Stop | Out-Null
            Register-JarvisOpenedApp -ProcessNames @("steam", "steamwebhelper")
            Write-Host "JARVIS opened steam:// protocol"
            exit 0
        } catch {}
        Show-Missing "JARVIS" "Steam не найден. Установи Steam или укажи путь установки."
        exit 1
    }
    "telegram" {
        $exe = Find-TelegramExe
        if ($exe) {
            Start-Process -FilePath $exe | Out-Null
            Register-JarvisOpenedApp -ProcessNames @("Telegram")
            Write-Host "JARVIS opened Telegram: $exe"
            exit 0
        }
        try {
            Start-Process "tg://" -ErrorAction Stop | Out-Null
            Register-JarvisOpenedApp -ProcessNames @("Telegram")
            Write-Host "JARVIS opened tg:// protocol"
            exit 0
        } catch {}
        Open-Url "https://web.telegram.org/k/"
    }
    "epic" {
        $candidates = @(
            (Join-Path $env:ProgramFiles "Epic Games\Launcher\Portal\Binaries\Win64\EpicGamesLauncher.exe"),
            (Join-Path ${env:ProgramFiles(x86)} "Epic Games\Launcher\Portal\Binaries\Win64\EpicGamesLauncher.exe")
        )
        foreach ($p in $candidates) {
            if ($p -and (Test-Path -LiteralPath $p)) {
                Start-Process -FilePath $p | Out-Null
                Register-JarvisOpenedApp -ProcessNames @("EpicGamesLauncher")
                exit 0
            }
        }
        Open-Url "https://store.epicgames.com"
    }
    "obs" {
        $candidates = @(
            (Join-Path $env:ProgramFiles "obs-studio\bin\64bit\obs64.exe"),
            (Join-Path ${env:ProgramFiles(x86)} "obs-studio\bin\64bit\obs64.exe")
        )
        foreach ($p in $candidates) {
            if ($p -and (Test-Path -LiteralPath $p)) {
                Start-Process -FilePath $p | Out-Null
                Register-JarvisOpenedApp -ProcessNames @("obs64", "obs32")
                exit 0
            }
        }
        Open-Url "https://obsproject.com"
    }
    "emoji" {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class JarvisKeys {
  [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
}
"@
        [JarvisKeys]::keybd_event(0x5B, 0, 0, [UIntPtr]::Zero)
        [JarvisKeys]::keybd_event(0xBE, 0, 0, [UIntPtr]::Zero)
        [JarvisKeys]::keybd_event(0xBE, 0, 2, [UIntPtr]::Zero)
        [JarvisKeys]::keybd_event(0x5B, 0, 2, [UIntPtr]::Zero)
        exit 0
    }
    "snip" {
        Start-Process "ms-screenclip:" | Out-Null
        exit 0
    }
    "gamebar" {
        Start-Process "ms-gamebar:" | Out-Null
        exit 0
    }
    "run" {
        (New-Object -ComObject Shell.Application).FileRun()
        exit 0
    }
    "chatgpt" { Open-Url "https://chatgpt.com" }
    "deepseek" { Open-Url "https://chat.deepseek.com" }
    "claude" { Open-Url "https://claude.ai" }
    "gemini" { Open-Url "https://gemini.google.com" }
}
