# Region picker: drag rectangle, write JSON to -OutFile (or stdout).
# ASCII-only body for Windows PowerShell 5.1. STA required. DPI-aware.
# Uses absolute screen mouse coords (not PointToScreen) so 125%/150% DPI
# and multi-monitor VirtualScreen offsets do not throw the window off-screen.
param(
    [string]$OutFile = ""
)

$ErrorActionPreference = "Stop"

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class JarvisDpi {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
"@ -ErrorAction SilentlyContinue
try { [void][JarvisDpi]::SetProcessDPIAware() } catch {}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
try { [Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false) } catch {}

$script:Result = $null
$script:Dragging = $false
$script:StartClient = New-Object Drawing.Point 0, 0
$script:CurClient = New-Object Drawing.Point 0, 0
$script:StartScreen = New-Object Drawing.Point 0, 0
$script:CurScreen = New-Object Drawing.Point 0, 0

$vs = [Windows.Forms.SystemInformation]::VirtualScreen

$form = New-Object Windows.Forms.Form
$form.Text = "JARVIS region"
$form.FormBorderStyle = [Windows.Forms.FormBorderStyle]::None
$form.StartPosition = [Windows.Forms.FormStartPosition]::Manual
$form.Bounds = $vs
$form.TopMost = $true
$form.ShowInTaskbar = $false
$form.BackColor = [Drawing.Color]::FromArgb(18, 24, 36)
$form.Opacity = 1.0
$form.Cursor = [Windows.Forms.Cursors]::Cross
$form.KeyPreview = $true
try {
    $prop = $form.GetType().GetProperty("DoubleBuffered", [Reflection.BindingFlags]"Instance,NonPublic")
    if ($prop) { $prop.SetValue($form, $true, $null) }
} catch {}

$hint = New-Object Windows.Forms.Label
$hint.AutoSize = $true
$hint.Font = New-Object Drawing.Font "Segoe UI", 13, ([Drawing.FontStyle]::Bold)
$hint.ForeColor = [Drawing.Color]::FromArgb(230, 236, 248)
$hint.BackColor = [Drawing.Color]::FromArgb(18, 24, 36)
$hint.Text = "Drag LMB to select window area   |   Esc cancel"
$hint.Location = New-Object Drawing.Point 36, 36
$form.Controls.Add($hint)

$form.Add_Paint({
    param($sender, $e)
    $dim = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(140, 8, 12, 20))
    $e.Graphics.FillRectangle($dim, $form.ClientRectangle)
    $dim.Dispose()
    if (-not $script:Dragging) { return }
    $x1 = [Math]::Min($script:StartClient.X, $script:CurClient.X)
    $y1 = [Math]::Min($script:StartClient.Y, $script:CurClient.Y)
    $x2 = [Math]::Max($script:StartClient.X, $script:CurClient.X)
    $y2 = [Math]::Max($script:StartClient.Y, $script:CurClient.Y)
    $w = $x2 - $x1
    $h = $y2 - $y1
    if ($w -lt 2 -or $h -lt 2) { return }
    $fill = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(70, 90, 170, 255))
    $pen = New-Object Drawing.Pen ([Drawing.Color]::FromArgb(240, 150, 210, 255), 2)
    $e.Graphics.FillRectangle($fill, $x1, $y1, $w, $h)
    $e.Graphics.DrawRectangle($pen, $x1, $y1, $w, $h)
    $fill.Dispose(); $pen.Dispose()
    $sz = "{0} x {1}" -f $w, $h
    $e.Graphics.DrawString($sz, $hint.Font, [Drawing.Brushes]::White, ($x1 + 8), ($y1 + 8))
})

$form.Add_MouseDown({
    param($s, $e)
    if ($e.Button -eq [Windows.Forms.MouseButtons]::Right) {
        $script:Result = $null
        $form.Close()
        return
    }
    if ($e.Button -ne [Windows.Forms.MouseButtons]::Left) { return }
    $script:Dragging = $true
    $script:StartClient = $e.Location
    $script:CurClient = $e.Location
    $mp = [Windows.Forms.Control]::MousePosition
    $script:StartScreen = $mp
    $script:CurScreen = $mp
    $form.Capture = $true
    $form.Invalidate()
})

$form.Add_MouseMove({
    param($s, $e)
    if (-not $script:Dragging) { return }
    $script:CurClient = $e.Location
    $script:CurScreen = [Windows.Forms.Control]::MousePosition
    $form.Invalidate()
})

$form.Add_MouseUp({
    param($s, $e)
    if (-not $script:Dragging) { return }
    if ($e.Button -ne [Windows.Forms.MouseButtons]::Left) { return }
    $script:Dragging = $false
    $form.Capture = $false
    $script:CurScreen = [Windows.Forms.Control]::MousePosition

    $x1 = [Math]::Min($script:StartScreen.X, $script:CurScreen.X)
    $y1 = [Math]::Min($script:StartScreen.Y, $script:CurScreen.Y)
    $x2 = [Math]::Max($script:StartScreen.X, $script:CurScreen.X)
    $y2 = [Math]::Max($script:StartScreen.Y, $script:CurScreen.Y)
    $w = $x2 - $x1
    $h = $y2 - $y1

    # Keep selection inside the virtual desktop (all monitors).
    if ($x1 -lt $vs.Left) { $x1 = $vs.Left }
    if ($y1 -lt $vs.Top) { $y1 = $vs.Top }
    if (($x1 + $w) -gt $vs.Right) { $w = $vs.Right - $x1 }
    if (($y1 + $h) -gt $vs.Bottom) { $h = $vs.Bottom - $y1 }

    if ($w -ge 200 -and $h -ge 120) {
        $script:Result = @{ x = [int]$x1; y = [int]$y1; w = [int]$w; h = [int]$h }
    } else {
        $script:Result = $null
    }
    $form.Close()
})

$form.Add_KeyDown({
    param($s, $e)
    if ($e.KeyCode -eq [Windows.Forms.Keys]::Escape) {
        $script:Result = $null
        $form.Close()
    }
})

$form.Add_Shown({
    $form.Activate()
    $form.BringToFront()
    [void][Windows.Forms.Application]::DoEvents()
})

[void]$form.ShowDialog()
$form.Dispose()

if ($null -eq $script:Result) {
    if ($OutFile) {
        [IO.File]::WriteAllText($OutFile, "CANCEL")
    }
    exit 2
}

$json = '{{"x":{0},"y":{1},"w":{2},"h":{3}}}' -f $script:Result.x, $script:Result.y, $script:Result.w, $script:Result.h
if ($OutFile) {
    [IO.File]::WriteAllText($OutFile, $json, [Text.UTF8Encoding]::new($false))
}
Write-Output $json
exit 0
