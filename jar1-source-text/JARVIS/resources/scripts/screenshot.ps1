$ErrorActionPreference = "Stop"

# This PC's ANSI code page is 1252. A redirected stdout then turns a Cyrillic
# Windows profile path into "????", and JARVIS reports "пустой путь".
try {
    $utf8 = New-Object System.Text.UTF8Encoding $false
    $OutputEncoding = $utf8
    [Console]::OutputEncoding = $utf8
} catch {}

# Must run before WinForms — otherwise Bounds are logical DIPs and CopyFromScreen
# grabs only the top-left chunk on 125%/150% scaling.
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class JarvisScreenshotDpi {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SetProcessDpiAwarenessContext(IntPtr value);
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
    public static void Enable() {
        const int PerMonitorV2 = -4;
        if (!SetProcessDpiAwarenessContext((IntPtr)PerMonitorV2)) {
            SetProcessDPIAware();
        }
    }
}
"@ -ErrorAction SilentlyContinue
try { [JarvisScreenshotDpi]::Enable() } catch {}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Full virtual desktop (all monitors), same idea as Win+PrtScn.
$vs = [System.Windows.Forms.SystemInformation]::VirtualScreen
$w = [Math]::Abs($vs.Width)
$h = [Math]::Abs($vs.Height)
if ($w -lt 1 -or $h -lt 1) {
    throw "Invalid virtual screen size ${w}x${h}"
}

$bmp = New-Object System.Drawing.Bitmap $w, $h
$g = [System.Drawing.Graphics]::FromImage($bmp)
try {
    $g.CopyFromScreen($vs.Left, $vs.Top, 0, 0, [System.Drawing.Size]::new($w, $h))
} finally {
    $g.Dispose()
}

$pictures = [Environment]::GetFolderPath("MyPictures")
$dir = Join-Path $pictures "JARVIS Screenshots"
[IO.Directory]::CreateDirectory($dir) | Out-Null
$path = Join-Path $dir ("screenshot_{0:yyyy-MM-dd_HH-mm-ss}.png" -f (Get-Date))

$bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
try { [System.Windows.Forms.Clipboard]::SetImage($bmp) } catch {}
$bmp.Dispose()

Write-Output $path
