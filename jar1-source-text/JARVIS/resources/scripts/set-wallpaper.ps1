# Set Windows desktop wallpaper.
# Modes: pick | latest-screenshot | latest-photo | random | path <file>
# Copies into Pictures\JARVIS Wallpapers so the wallpaper survives if the source moves.
# ASCII-only for Windows PowerShell 5.1. Use -STA for pick (OpenFileDialog).
param(
    [Parameter(Position = 0)]
    [ValidateSet("pick", "latest-screenshot", "latest-photo", "random", "path")]
    [string]$Mode = "pick",

    [Parameter(Position = 1)]
    [string]$Path = ""
)

$ErrorActionPreference = "Stop"

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class JarvisWallpaper {
  public const uint SPI_SETDESKWALLPAPER = 0x0014;
  public const uint SPIF_UPDATEINIFILE = 0x01;
  public const uint SPIF_SENDCHANGE = 0x02;
  [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  public static extern bool SystemParametersInfo(uint uiAction, uint uiParam, string pvParam, uint fWinIni);
}
"@ -ErrorAction Stop

function Get-PicturesRoot {
    $p = [Environment]::GetFolderPath("MyPictures")
    if ([string]::IsNullOrWhiteSpace($p)) {
        $p = Join-Path $env:USERPROFILE "Pictures"
    }
    return $p
}

function Get-WallpaperVault {
    $dir = Join-Path (Get-PicturesRoot) "JARVIS Wallpapers"
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    return $dir
}

function Test-IsImageFile([string]$file) {
    if ([string]::IsNullOrWhiteSpace($file)) { return $false }
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { return $false }
    $ext = [IO.Path]::GetExtension($file).ToLowerInvariant()
    return $ext -in @(".jpg", ".jpeg", ".png", ".bmp", ".webp", ".jfif")
}

function Get-ImageFiles([string]$dir) {
    if (-not (Test-Path -LiteralPath $dir)) { return @() }
    Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue |
        Where-Object { Test-IsImageFile $_.FullName } |
        Sort-Object LastWriteTime -Descending
}

function Copy-ToVault([string]$src) {
    $vault = Get-WallpaperVault
    $ext = [IO.Path]::GetExtension($src)
    if ([string]::IsNullOrWhiteSpace($ext)) { $ext = ".jpg" }
    $name = "wallpaper_{0:yyyyMMdd_HHmmss}{1}" -f (Get-Date), $ext.ToLowerInvariant()
    $dst = Join-Path $vault $name
    Copy-Item -LiteralPath $src -Destination $dst -Force
    return $dst
}

function Set-DesktopWallpaper([string]$file) {
    if (-not (Test-IsImageFile $file)) {
        throw "Not an image file: $file"
    }
    $full = (Resolve-Path -LiteralPath $file).Path
    $stable = Copy-ToVault $full

    # Pick style by image vs screen size so small downloads are not mushy Fill-upscales.
    # 10 = Fill (cover), 6 = Fit (letterbox), 0 = Center (1:1, no upscale).
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $screen = [Windows.Forms.Screen]::PrimaryScreen.Bounds
    $sw = [Math]::Max(1, $screen.Width)
    $sh = [Math]::Max(1, $screen.Height)
    $img = [Drawing.Image]::FromFile($stable)
    $iw = $img.Width
    $ih = $img.Height
    $img.Dispose()

    $style = "10"
    $modeName = "Fill"
    if ($iw -lt $sw -or $ih -lt $sh) {
        # Undersized: Fit keeps sharpness; tiny images stay Center (no stretch).
        if ($iw -lt ([int]($sw * 0.7)) -or $ih -lt ([int]($sh * 0.7))) {
            $style = "0"
            $modeName = "Center"
        } else {
            $style = "6"
            $modeName = "Fit"
        }
    }

    $desk = "HKCU:\Control Panel\Desktop"
    Set-ItemProperty -Path $desk -Name WallpaperStyle -Value $style -Type String
    Set-ItemProperty -Path $desk -Name TileWallpaper -Value "0" -Type String
    Set-ItemProperty -Path $desk -Name Wallpaper -Value $stable -Type String

    $ok = [JarvisWallpaper]::SystemParametersInfo(
        [JarvisWallpaper]::SPI_SETDESKWALLPAPER,
        0,
        $stable,
        ([JarvisWallpaper]::SPIF_UPDATEINIFILE -bor [JarvisWallpaper]::SPIF_SENDCHANGE)
    )
    if (-not $ok) {
        $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw "SystemParametersInfo failed win32=$err"
    }
    Write-Host ("JARVIS wallpaper: set OK name={0} img={1}x{2} screen={3}x{4} mode={5}" -f `
        [IO.Path]::GetFileName($stable), $iw, $ih, $sw, $sh, $modeName)
    return $stable
}

function Invoke-PickImage {
    Add-Type -AssemblyName System.Windows.Forms
    $dlg = New-Object Windows.Forms.OpenFileDialog
    $dlg.Title = "JARVIS - wallpaper"
    $dlg.Filter = "Images|*.jpg;*.jpeg;*.png;*.bmp;*.webp;*.jfif|All files|*.*"
    $dlg.FilterIndex = 1
    $dlg.Multiselect = $false
    $dlg.CheckFileExists = $true
    $start = Get-PicturesRoot
    if (Test-Path -LiteralPath $start) { $dlg.InitialDirectory = $start }
    $res = $dlg.ShowDialog()
    if ($res -ne [Windows.Forms.DialogResult]::OK) {
        Write-Host "JARVIS wallpaper: cancelled"
        exit 2
    }
    return $dlg.FileName
}

function Get-LatestScreenshot {
    $dir = Join-Path (Get-PicturesRoot) "JARVIS Screenshots"
    $files = @(Get-ImageFiles $dir)
    if ($files.Count -eq 0) { return $null }
    return $files[0].FullName
}

function Get-LatestPhoto {
    $dir = Join-Path (Get-PicturesRoot) "JARVIS"
    $files = @(Get-ImageFiles $dir)
    if ($files.Count -eq 0) { return $null }
    return $files[0].FullName
}

function Get-RandomWallpaperSource {
    $pics = Get-PicturesRoot
    $dirs = @(
        (Join-Path $pics "JARVIS Wallpapers"),
        (Join-Path $pics "JARVIS"),
        (Join-Path $pics "JARVIS Screenshots"),
        $pics
    )
    $pool = New-Object System.Collections.Generic.List[string]
    foreach ($d in $dirs) {
        foreach ($f in (Get-ImageFiles $d)) {
            if (-not $pool.Contains($f.FullName)) { [void]$pool.Add($f.FullName) }
        }
    }
    if ($pool.Count -eq 0) { return $null }
    $i = Get-Random -Minimum 0 -Maximum $pool.Count
    return $pool[$i]
}

$src = $null
switch ($Mode) {
    "pick" {
        $src = Invoke-PickImage
    }
    "latest-screenshot" {
        $src = Get-LatestScreenshot
        if (-not $src) {
            Write-Host "JARVIS wallpaper: no screenshots in Pictures\JARVIS Screenshots"
            exit 3
        }
    }
    "latest-photo" {
        $src = Get-LatestPhoto
        if (-not $src) {
            Write-Host "JARVIS wallpaper: no images in Pictures\JARVIS"
            exit 3
        }
    }
    "random" {
        $src = Get-RandomWallpaperSource
        if (-not $src) {
            Write-Host "JARVIS wallpaper: no images in Pictures"
            exit 3
        }
    }
    "path" {
        if ([string]::IsNullOrWhiteSpace($Path)) {
            Write-Host "JARVIS wallpaper: path required"
            exit 1
        }
        $src = $Path
    }
}

try {
    [void](Set-DesktopWallpaper $src)
    exit 0
} catch {
    Write-Host ("JARVIS wallpaper: FAIL {0}" -f $_.Exception.Message)
    exit 1
}
