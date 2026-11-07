# JARVIS HUD design tokens + chrome helpers.
# Dot-source from overlay scripts. One accent: steel cyan (#5CF6F0) - matches frontend --j-cyan.
# No purple. Motion: scale + soft glow (blur), CubicEase - not elastic bounce spam.

$script:JarvisHudTheme = [ordered]@{
    Accent        = "#FF5CF6F0"
    AccentSoft    = "#665CF6F0"
    AccentLine    = "#995CF6F0"
    AccentDimBg   = "#225CF6F0"
    AccentDarkFg  = "#FF061014"
    PanelBg       = "#F20A0E14"
    PanelInner    = "#FF0C1218"
    HeaderBg      = "#22101820"
    FooterBg      = "#18101820"
    Border        = "#FF1E3A44"
    BorderSoft    = "#FF243848"
    Text          = "#FFF2F5F8"
    TextMuted     = "#FF8A9BA8"
    TextFaint     = "#FF5C6B76"
    Danger        = "#FFFF7B7B"
    DangerFg      = "#FFFFC9C9"
    DangerBg      = "#33FF7B7B"
    DangerLine    = "#88FF7B7B"
    Ok            = "#FF5EE4B0"
    Warn          = "#FFFFC14A"
    GlowFill      = "#88060A12"
    GlowOpacity   = "0.55"
    GlowBlur      = "18"
    GlowMargin    = "12"
    GhostBtnBg    = "#FF121A22"
    GhostBtnBg2   = "#FF12161C"
    # Sampled from Baos settings modal (2026-05-28 screenshot).
    BtnMatte      = "#FF1F2642"
    BtnMatteHot   = "#FF2A3355"
    BtnGhost      = "#FF2E353F"
    BtnGhostHot   = "#FF3A424C"
    BtnInCard     = "#FF333F59"
    BtnInCardHot  = "#FF3D4A68"
    BtnHairline   = "#00FFFFFF"
    BtnOnMatte    = "#FFFFFFFF"
    FontUi        = "Segoe UI Variable Text, Segoe UI Semibold, Segoe UI"
    FontMono      = "Cascadia Mono, Consolas, Courier New"
    Corner        = "14"
    CornerSm      = "10"
    AppearMs      = 340
    FadeMs        = 180
}

function Get-JarvisHudTheme {
    return $script:JarvisHudTheme
}

function Escape-JarvisHudText {
    param([AllowNull()][string]$Text)
    if ($null -eq $Text) { return "" }
    # XML entity escape + WPF: only escape '{' as '{}' so '{foo}' is literal (do not rewrite '}').
    $x = [System.Security.SecurityElement]::Escape($Text)
    return ($x -replace '\{', '{}{')
}

function Ensure-JarvisHudAssemblies {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml -ErrorAction Stop
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
    Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
    # WPF DispatcherFrame needs an Application instance in headless PowerShell hosts.
    if ($null -eq [System.Windows.Application]::Current) {
        $app = New-Object System.Windows.Application
        $app.ShutdownMode = [System.Windows.ShutdownMode]::OnExplicitShutdown
    }
}

function Ensure-JarvisHudWin32 {
    if ("JarvisHudWin32" -as [type]) { return }
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class JarvisHudWin32 {
  public const int GWL_EXSTYLE = -20;
  public const int WS_EX_NOACTIVATE = 0x08000000;
  public const int WS_EX_TOOLWINDOW = 0x00000080;
  public const int WS_EX_TOPMOST = 0x00000008;
  public static readonly IntPtr HWND_TOPMOST = new IntPtr(-1);
  public const uint SWP_NOSIZE = 0x0001;
  public const uint SWP_NOMOVE = 0x0002;
  public const uint SWP_NOACTIVATE = 0x0010;
  public const uint SWP_SHOWWINDOW = 0x0040;
  [DllImport("user32.dll", EntryPoint="GetWindowLongPtr", SetLastError=true)]
  public static extern IntPtr GetWindowLongPtr64(IntPtr hWnd, int nIndex);
  [DllImport("user32.dll", EntryPoint="SetWindowLongPtr", SetLastError=true)]
  public static extern IntPtr SetWindowLongPtr64(IntPtr hWnd, int nIndex, IntPtr dwNewLong);
  [DllImport("user32.dll", EntryPoint="GetWindowLong", SetLastError=true)]
  public static extern int GetWindowLong32(IntPtr hWnd, int nIndex);
  [DllImport("user32.dll", EntryPoint="SetWindowLong", SetLastError=true)]
  public static extern int SetWindowLong32(IntPtr hWnd, int nIndex, int dwNewLong);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);

  public static IntPtr GetWindowLongPtr(IntPtr hWnd, int nIndex) {
    if (IntPtr.Size == 8) return GetWindowLongPtr64(hWnd, nIndex);
    return new IntPtr(GetWindowLong32(hWnd, nIndex));
  }
  public static IntPtr SetWindowLongPtr(IntPtr hWnd, int nIndex, IntPtr dwNewLong) {
    if (IntPtr.Size == 8) return SetWindowLongPtr64(hWnd, nIndex, dwNewLong);
    return new IntPtr(SetWindowLong32(hWnd, nIndex, dwNewLong.ToInt32()));
  }
}
"@
}

function Set-JarvisHudOverlayStyle {
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Window]$Window,
        [switch]$StealFocus
    )
    Ensure-JarvisHudWin32
    $helper = New-Object System.Windows.Interop.WindowInteropHelper($Window)
    $hwnd = $helper.EnsureHandle()
    $exPtr = [JarvisHudWin32]::GetWindowLongPtr($hwnd, [JarvisHudWin32]::GWL_EXSTYLE)
    $ex = $exPtr.ToInt64()
    $ex = $ex -bor [JarvisHudWin32]::WS_EX_TOOLWINDOW -bor [JarvisHudWin32]::WS_EX_TOPMOST
    if (-not $StealFocus) {
        $ex = $ex -bor [JarvisHudWin32]::WS_EX_NOACTIVATE
    }
    [void][JarvisHudWin32]::SetWindowLongPtr($hwnd, [JarvisHudWin32]::GWL_EXSTYLE, [IntPtr]::new($ex))
    [void][JarvisHudWin32]::SetWindowPos(
        $hwnd,
        [JarvisHudWin32]::HWND_TOPMOST,
        0, 0, 0, 0,
        ([JarvisHudWin32]::SWP_NOMOVE -bor [JarvisHudWin32]::SWP_NOSIZE -bor [JarvisHudWin32]::SWP_NOACTIVATE -bor [JarvisHudWin32]::SWP_SHOWWINDOW)
    )
}

function Place-JarvisHudTopRight {
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Window]$Window,
        [double]$MarginX = 24,
        [double]$MarginY = 48
    )
    try {
        $wa = [System.Windows.SystemParameters]::WorkArea
        $w = if ($Window.ActualWidth -gt 1) { $Window.ActualWidth } else { $Window.Width }
        $Window.Left = [Math]::Max(12, $wa.Right - $w - $MarginX)
        $Window.Top = [Math]::Max(12, $wa.Top + $MarginY)
    } catch {
        $Window.Left = 40
        $Window.Top = 40
    }
}

function Get-JarvisHudAppearStoryboardXaml {
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $appearSec = ([Math]::Round(($script:JarvisHudTheme.AppearMs) / 1000.0, 2)).ToString("0.00", $inv)
    $fadeSec = ([Math]::Round(($script:JarvisHudTheme.FadeMs) / 1000.0, 2)).ToString("0.00", $inv)
    $fadeInSec = ([Math]::Round([Math]::Min(($script:JarvisHudTheme.AppearMs) / 1000.0, 0.22), 2)).ToString("0.00", $inv)
    return @"
    <Storyboard x:Key="Appear">
      <DoubleAnimation Storyboard.TargetName="RootScale" Storyboard.TargetProperty="ScaleX"
                       From="0.88" To="1.0" Duration="0:0:$appearSec">
        <DoubleAnimation.EasingFunction><CubicEase EasingMode="EaseOut"/></DoubleAnimation.EasingFunction>
      </DoubleAnimation>
      <DoubleAnimation Storyboard.TargetName="RootScale" Storyboard.TargetProperty="ScaleY"
                       From="0.88" To="1.0" Duration="0:0:$appearSec">
        <DoubleAnimation.EasingFunction><CubicEase EasingMode="EaseOut"/></DoubleAnimation.EasingFunction>
      </DoubleAnimation>
      <DoubleAnimation Storyboard.TargetName="RootTranslate" Storyboard.TargetProperty="Y"
                       From="14" To="0" Duration="0:0:$appearSec">
        <DoubleAnimation.EasingFunction><CubicEase EasingMode="EaseOut"/></DoubleAnimation.EasingFunction>
      </DoubleAnimation>
      <DoubleAnimation Storyboard.TargetProperty="Opacity" From="0" To="1" Duration="0:0:$fadeInSec"/>
      <DoubleAnimation Storyboard.TargetName="GlowBorder" Storyboard.TargetProperty="Opacity"
                       From="0.85" To="0.42" Duration="0:0:0.55">
        <DoubleAnimation.EasingFunction><CubicEase EasingMode="EaseOut"/></DoubleAnimation.EasingFunction>
      </DoubleAnimation>
    </Storyboard>
    <Storyboard x:Key="Pulse">
      <DoubleAnimation Storyboard.TargetName="GlowBorder" Storyboard.TargetProperty="Opacity"
                       From="0.38" To="0.72" Duration="0:0:1.15" AutoReverse="True" RepeatBehavior="Forever">
        <DoubleAnimation.EasingFunction><SineEase EasingMode="EaseInOut"/></DoubleAnimation.EasingFunction>
      </DoubleAnimation>
    </Storyboard>
    <Storyboard x:Key="Dismiss">
      <DoubleAnimation Storyboard.TargetName="RootScale" Storyboard.TargetProperty="ScaleX"
                       From="1.0" To="0.94" Duration="0:0:$fadeSec">
        <DoubleAnimation.EasingFunction><CubicEase EasingMode="EaseIn"/></DoubleAnimation.EasingFunction>
      </DoubleAnimation>
      <DoubleAnimation Storyboard.TargetName="RootScale" Storyboard.TargetProperty="ScaleY"
                       From="1.0" To="0.94" Duration="0:0:$fadeSec">
        <DoubleAnimation.EasingFunction><CubicEase EasingMode="EaseIn"/></DoubleAnimation.EasingFunction>
      </DoubleAnimation>
      <DoubleAnimation Storyboard.TargetProperty="Opacity" From="1" To="0" Duration="0:0:$fadeSec"/>
    </Storyboard>
"@
}

function Get-JarvisHudPrimaryButtonTemplate {
    $r = $script:JarvisHudTheme.CornerSm
    return @"
              <Button.Template>
                <ControlTemplate TargetType="Button">
                  <Border x:Name="b" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
                          BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="$r"
                          Padding="{TemplateBinding Padding}">
                    <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                  </Border>
                  <ControlTemplate.Triggers>
                    <Trigger Property="IsMouseOver" Value="True">
                      <Setter TargetName="b" Property="Opacity" Value="0.88"/>
                    </Trigger>
                    <Trigger Property="IsPressed" Value="True">
                      <Setter TargetName="b" Property="Opacity" Value="0.74"/>
                    </Trigger>
                    <Trigger Property="IsEnabled" Value="False">
                      <Setter TargetName="b" Property="Opacity" Value="0.45"/>
                    </Trigger>
                  </ControlTemplate.Triggers>
                </ControlTemplate>
              </Button.Template>
"@
}

function Get-JarvisHud3dButtonTemplateXaml {
    param(
        [string]$Top,
        [string]$Mid,
        [string]$Bot,
        [string]$TopHot,
        [string]$BotHot,
        [double]$Radius = 8,
        [string]$NamePrefix = ""
    )
    $r = ([Math]::Round($Radius, 1)).ToString([System.Globalization.CultureInfo]::InvariantCulture)
    $fc = $NamePrefix + "face"
    $ht = $NamePrefix + "hot"
    return @"
                <ControlTemplate TargetType="Button">
                  <Border x:Name="$fc" CornerRadius="$r" BorderThickness="1" BorderBrush="#22FFFFFF"
                          Background="{TemplateBinding Background}" Padding="{TemplateBinding Padding}">
                    <Grid>
                      <Border x:Name="$ht" CornerRadius="$r" Background="#14FFFFFF" Opacity="0" IsHitTestVisible="False"/>
                      <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                    </Grid>
                  </Border>
                  <ControlTemplate.Triggers>
                    <Trigger Property="IsMouseOver" Value="True">
                      <Setter TargetName="$ht" Property="Opacity" Value="1"/>
                    </Trigger>
                    <Trigger Property="IsPressed" Value="True">
                      <Setter TargetName="$ht" Property="Opacity" Value="0.35"/>
                      <Setter TargetName="$fc" Property="Opacity" Value="0.92"/>
                    </Trigger>
                    <Trigger Property="IsEnabled" Value="False">
                      <Setter TargetName="$fc" Property="Opacity" Value="0.45"/>
                    </Trigger>
                  </ControlTemplate.Triggers>
                </ControlTemplate>
"@
}

function Get-JarvisHud3dButtonTemplate {
    param(
        [string]$Top,
        [string]$Mid,
        [string]$Bot,
        [string]$TopHot,
        [string]$BotHot,
        [double]$Radius = 8,
        [string]$NamePrefix = "t"
    )
    $inner = (Get-JarvisHud3dButtonTemplateXaml -Top $Top -Mid $Mid -Bot $Bot -TopHot $TopHot -BotHot $BotHot -Radius $Radius -NamePrefix $NamePrefix).Trim()
    $xaml = $inner -replace '^<ControlTemplate TargetType="Button">', '<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" TargetType="Button">'
    return [Windows.Markup.XamlReader]::Parse($xaml)
}

function Get-JarvisHudRoundedButtonTemplate {
    param(
        [double]$Radius = 12,
        [string]$Hover = ""
    )
    $r = ([Math]::Round($Radius, 1)).ToString([System.Globalization.CultureInfo]::InvariantCulture)
    $hoverXml = if ([string]::IsNullOrWhiteSpace($Hover)) {
        '      <Setter TargetName="b" Property="Opacity" Value="0.86"/>'
    } else {
        "      <Setter TargetName=`"b`" Property=`"Background`" Value=`"$Hover`"/>"
    }
    $xaml = @"
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" TargetType="Button">
  <Border x:Name="b" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
          BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="$r"
          Padding="{TemplateBinding Padding}">
    <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
  </Border>
  <ControlTemplate.Triggers>
    <Trigger Property="IsMouseOver" Value="True">
$hoverXml
    </Trigger>
    <Trigger Property="IsPressed" Value="True">
      <Setter TargetName="b" Property="Opacity" Value="0.82"/>
    </Trigger>
    <Trigger Property="IsEnabled" Value="False">
      <Setter TargetName="b" Property="Opacity" Value="0.45"/>
    </Trigger>
  </ControlTemplate.Triggers>
</ControlTemplate>
"@
    return [Windows.Markup.XamlReader]::Parse($xaml)
}

function Set-JarvisHudMatteButton {
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Controls.Button]$Button,
        [ValidateSet("primary", "secondary", "incard")]
        [string]$Kind = "secondary",
        [System.Windows.Controls.ControlTemplate]$Template = $null
    )
    $th = Get-JarvisHudTheme
    if ($null -ne $Template) { $Button.Template = $Template }
    $bc = [System.Windows.Media.BrushConverter]::new()
    $Button.Foreground = $bc.ConvertFromString($th.BtnOnMatte)
    $Button.BorderBrush = $bc.ConvertFromString("#00FFFFFF")
    $Button.BorderThickness = [System.Windows.Thickness]::new(0)
    if ($Kind -eq "primary") {
        $Button.Background = $bc.ConvertFromString($th.BtnMatte)
    } elseif ($Kind -eq "incard") {
        $Button.Background = $bc.ConvertFromString($th.BtnInCard)
    } else {
        $Button.Background = $bc.ConvertFromString($th.BtnGhost)
    }
    $Button.FontFamily = [System.Windows.Media.FontFamily]::new("Segoe UI")
    $Button.FontWeight = [System.Windows.FontWeights]::Medium
    $Button.Cursor = [System.Windows.Input.Cursors]::Hand
    $Button.Focusable = $false
}

function Get-JarvisHudInkBrush {
    # Same as theme Text — never SystemColors.WindowText (black on dark HUD).
    return [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.Color]::FromRgb(0xF2, 0xF5, 0xF8)
    )
}

function Set-JarvisHudLayeredWindow([System.Windows.Window]$Window) {
    if ($null -eq $Window) { return }
    try { $Window.UseLayoutRounding = $true } catch {}
    try { $Window.SnapsToDevicePixels = $true } catch {}
    try {
        [System.Windows.Media.TextOptions]::SetTextFormattingMode(
            $Window, [System.Windows.Media.TextFormattingMode]::Display)
        [System.Windows.Media.TextOptions]::SetTextRenderingMode(
            $Window, [System.Windows.Media.TextRenderingMode]::ClearType)
    } catch {}
}

function Set-JarvisHudInputInk {
    param(
        [Parameter(Mandatory = $true)][System.Windows.Controls.TextBox]$Box,
        [System.Windows.Controls.TextBlock]$Ink,
        [System.Windows.Controls.TextBlock]$Hint
    )
    $inkBrush = Get-JarvisHudInkBrush
    $box.Foreground = [System.Windows.Media.Brushes]::Transparent
    $box.CaretBrush = $inkBrush
    $box.Background = [System.Windows.Media.Brushes]::Transparent
    $box.BorderThickness = [System.Windows.Thickness]::new(0)
    $box.SelectionBrush = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.Color]::FromArgb(0x99, 0x5C, 0xF6, 0xF0)
    )
    try { $box.SelectionOpacity = 0.45 } catch {}

    $sync = {
        try {
            $t = [string]$box.Text
            $empty = [string]::IsNullOrWhiteSpace($t)
            if ($null -ne $Ink) {
                $Ink.Text = $t
                $Ink.Foreground = $inkBrush
                $Ink.Visibility = if ($empty) { "Hidden" } else { "Visible" }
            }
            if ($null -ne $Hint) {
                $Hint.Visibility = if ($empty) { "Visible" } else { "Hidden" }
            }
        } catch {}
    }.GetNewClosure()

    $box.Add_TextChanged($sync)
    & $sync
}
