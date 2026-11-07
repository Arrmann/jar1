param(
    [switch]$Ui,
    [string]$Text = "",
    [string]$TextFile = "",
    [ValidateSet("auto","ru","en")]
    [string]$TargetLang = "auto",
    [int]$MaxChars = 2500,
    [int]$CursorX = -1,
    [int]$CursorY = -1,
    [int]$AutoCloseSec = 90
)

# JARVIS translate HUD - LLM via settings API key. ASCII-only source (WinPS 5.1).
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "_jarvis-hidden-process.ps1")

# Warm PowerShell standby is MTA (no -STA). WPF + clipboard need STA or the
# process dies before any window appears — common on customer PCs.
$apt = [Threading.Thread]::CurrentThread.GetApartmentState()
if ($apt -ne [Threading.ApartmentState]::STA) {
    $reArgs = @(
        "-NoProfile", "-NonInteractive", "-STA", "-ExecutionPolicy", "Bypass",
        "-File", $PSCommandPath,
        "-TargetLang", $TargetLang,
        "-MaxChars", "$MaxChars",
        "-CursorX", "$CursorX",
        "-CursorY", "$CursorY",
        "-AutoCloseSec", "$AutoCloseSec"
    )
    if ($Ui) { $reArgs += "-Ui" }
    if (-not [string]::IsNullOrWhiteSpace($Text)) { $reArgs += @("-Text", $Text) }
    if (-not [string]::IsNullOrWhiteSpace($TextFile)) { $reArgs += @("-TextFile", $TextFile) }
    Start-JarvisHiddenProcess -FilePath "powershell.exe" -ArgumentList $reArgs | Out-Null
    exit 0
}

if ($TextFile -and (Test-Path -LiteralPath $TextFile)) {
    try {
        $fromFile = [IO.File]::ReadAllText($TextFile, [Text.UTF8Encoding]::new($false)).Trim()
        if (-not [string]::IsNullOrWhiteSpace($fromFile)) { $Text = $fromFile }
    } catch {}
    try { Remove-Item -LiteralPath $TextFile -Force -ErrorAction SilentlyContinue } catch {}
}

function Get-CursorPosRaw {
    if (-not ("JarvisCursor4" -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class JarvisCursor4 {
  [StructLayout(LayoutKind.Sequential)]
  public struct POINT { public int X; public int Y; }
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT lpPoint);
}
"@ -ErrorAction SilentlyContinue
    }
    $p = New-Object JarvisCursor4+POINT
    [void][JarvisCursor4]::GetCursorPos([ref]$p)
    return @{ X = [int]$p.X; Y = [int]$p.Y }
}

function Ensure-SelectionApi {
    if ("JarvisSelectCopy" -as [type]) { return }
    Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Diagnostics;
using System.Runtime.InteropServices;
public static class JarvisSelectCopy {
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)]
  public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
  public const uint KEYEVENTF_KEYUP = 0x0002;
  public const byte VK_CONTROL = 0x11;
  public const byte VK_C = 0x43;

  static bool IsJarvisProcess(string name) {
    name = (name ?? "").ToLowerInvariant();
    return name == "jarvis-gui" || name == "jarvis-app" || name == "jarvis-run";
  }

  public static IntPtr FindTargetWindow() {
    IntPtr fg = GetForegroundWindow();
    uint pid = 0;
    GetWindowThreadProcessId(fg, out pid);
    try {
      var p = Process.GetProcessById((int)pid);
      if (!IsJarvisProcess(p.ProcessName)) return fg;
    } catch {}

    IntPtr best = IntPtr.Zero;
    EnumWindows((hWnd, lLabel) => {
      if (!IsWindowVisible(hWnd)) return true;
      uint wpid = 0;
      GetWindowThreadProcessId(hWnd, out wpid);
      try {
        var p = Process.GetProcessById((int)wpid);
        if (IsJarvisProcess(p.ProcessName)) return true;
      } catch { return true; }
      var title = new StringBuilder(256);
      GetWindowText(hWnd, title, title.Capacity);
      if (title.Length < 1) return true;
      best = hWnd;
      return false;
    }, IntPtr.Zero);
    return best != IntPtr.Zero ? best : fg;
  }

  public static void FocusAndCopy(IntPtr hWnd) {
    if (hWnd == IntPtr.Zero) return;
    uint unused = 0;
    uint curTid = GetCurrentThreadId();
    IntPtr fg = GetForegroundWindow();
    uint fgTid = fg != IntPtr.Zero ? GetWindowThreadProcessId(fg, out unused) : 0;
    uint targetTid = GetWindowThreadProcessId(hWnd, out unused);
    if (fgTid != 0 && fgTid != curTid) AttachThreadInput(curTid, fgTid, true);
    if (targetTid != 0 && targetTid != curTid && targetTid != fgTid) AttachThreadInput(curTid, targetTid, true);
    ShowWindow(hWnd, 5);
    SetForegroundWindow(hWnd);
    System.Threading.Thread.Sleep(140);
    for (int i = 0; i < 2; i++) {
      keybd_event(VK_CONTROL, 0, 0, UIntPtr.Zero);
      keybd_event(VK_C, 0, 0, UIntPtr.Zero);
      keybd_event(VK_C, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
      keybd_event(VK_CONTROL, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
      System.Threading.Thread.Sleep(90);
    }
    System.Threading.Thread.Sleep(100);
    if (fgTid != 0 && fgTid != curTid) AttachThreadInput(curTid, fgTid, false);
    if (targetTid != 0 && targetTid != curTid && targetTid != fgTid) AttachThreadInput(curTid, targetTid, false);
  }
}
"@
}

function Get-ClipboardTextSafe {
    for ($i = 0; $i -lt 6; $i++) {
        try {
            $clip = [System.Windows.Forms.Clipboard]::GetText()
            if ($null -ne $clip -and -not [string]::IsNullOrWhiteSpace($clip)) {
                return $clip.Trim()
            }
        } catch {}
        Start-Sleep -Milliseconds 60
    }
    return ""
}

function Get-SelectionOrClipboard([string]$preferred) {
    if (-not [string]::IsNullOrWhiteSpace($preferred)) { return $preferred.Trim() }

    Ensure-SelectionApi
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue

    $before = ""
    try { $before = [System.Windows.Forms.Clipboard]::GetText() } catch {}
    if ($null -eq $before) { $before = "" }

    $target = [JarvisSelectCopy]::FindTargetWindow()
    try { [JarvisSelectCopy]::FocusAndCopy($target) } catch {}

    $clip = Get-ClipboardTextSafe
    $result = ""
    if (-not [string]::IsNullOrWhiteSpace($clip) -and $clip -ne $before.Trim()) {
        $result = $clip
    } elseif (-not [string]::IsNullOrWhiteSpace($clip)) {
        $result = $clip
    } elseif (-not [string]::IsNullOrWhiteSpace($before)) {
        $result = $before.Trim()
    }
    try {
        if (-not [string]::IsNullOrEmpty($before)) {
            [System.Windows.Forms.Clipboard]::SetText($before)
        }
    } catch {}
    return $result
}

function Show-JarvisToast([string]$title, [string]$message, [string]$kind = "warn") {
    $toast = Join-Path $PSScriptRoot "toast.ps1"
    if (-not (Test-Path -LiteralPath $toast)) { return }
    $tmpT = Join-Path $env:TEMP ("jarvis-toast-t-" + [guid]::NewGuid().ToString("N") + ".txt")
    $tmpM = Join-Path $env:TEMP ("jarvis-toast-m-" + [guid]::NewGuid().ToString("N") + ".txt")
    [IO.File]::WriteAllText($tmpT, [string]$title, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($tmpM, [string]$message, [Text.UTF8Encoding]::new($false))
    # Prefer a windowless native spawn. Do not pass a hidden-window flag.
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-NoProfile -STA -NonInteractive -ExecutionPolicy Bypass -File `"$toast`" -Ui -TitleFile `"$tmpT`" -MessageFile `"$tmpM`" -Kind $kind -DurationMs 4200"
    $psi.CreateNoWindow = $true
    $psi.UseShellExecute = $false
    [void][System.Diagnostics.Process]::Start($psi)
}

# Capture selection first, then reopen as -Ui (toast-style hidden STA spawn).
if (-not $Ui) {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
    $c = Get-CursorPosRaw
    if ([string]::IsNullOrWhiteSpace($Text)) {
        $Text = Get-SelectionOrClipboard ""
    }
    $tmp = Join-Path $env:TEMP ("jarvis-translate-" + [guid]::NewGuid().ToString("N") + ".txt")
    [IO.File]::WriteAllText($tmp, [string]$Text, [Text.UTF8Encoding]::new($false))
    $argList = @(
        "-NoProfile", "-NonInteractive", "-STA", "-ExecutionPolicy", "Bypass",
        "-File", $PSCommandPath,
        "-Ui",
        "-TargetLang", $TargetLang,
        "-CursorX", "$($c.X)",
        "-CursorY", "$($c.Y)",
        "-AutoCloseSec", "$AutoCloseSec",
        "-TextFile", $tmp
    )
    Start-JarvisHiddenProcess -FilePath "powershell.exe" -ArgumentList $argList | Out-Null
    exit 0
}

try {
    $mutex = [System.Threading.Mutex]::new($false, "Local\JarvisTranslateHud")
    if (-not $mutex.WaitOne(0)) {
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
            $_.ProcessId -ne $PID -and $_.CommandLine -and ($_.CommandLine -match 'translate-hud\.ps1')
        } | ForEach-Object {
            try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch {}
        }
        Start-Sleep -Milliseconds 220
        if (-not $mutex.WaitOne(0)) { exit 0 }
    }
} catch {}

try {
. (Join-Path $PSScriptRoot "jarvis-hud-theme.ps1")
. (Join-Path $PSScriptRoot "_jarvis-llm.ps1")
. (Join-Path $PSScriptRoot "_jarvis-translate.ps1")
Ensure-JarvisHudAssemblies
Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
$hud = Get-JarvisHudTheme

function U8([byte[]]$b) { return [Text.Encoding]::UTF8.GetString($b) }

$L = @{
    TitleSrc   = U8 @(0xD0,0x98,0xD0,0xA1,0xD0,0xA5,0xD0,0x9E,0xD0,0x94,0xD0,0x9D,0xD0,0xAB,0xD0,0x99) # ISHODNYY
    TitleDst   = U8 @(0xD0,0x9F,0xD0,0x95,0xD0,0xA0,0xD0,0x95,0xD0,0x92,0xD0,0x9E,0xD0,0x94) # PEREVOD
    Copy       = U8 @(0xD0,0x9A,0xD0,0xBE,0xD0,0xBF,0xD0,0xB8,0xD1,0x80,0xD0,0xBE,0xD0,0xB2,0xD0,0xB0,0xD1,0x82,0xD1,0x8C)
    Close      = U8 @(0xD0,0x97,0xD0,0xB0,0xD0,0xBA,0xD1,0x80,0xD1,0x8B,0xD1,0x82,0xD1,0x8C)
    StatusWait = U8 @(0xD0,0xBF,0xD0,0xB5,0xD1,0x80,0xD0,0xB5,0xD0,0xB2,0xD0,0xBE,0xD0,0xB4,0xE2,0x80,0xA6) # perevod...
    StatusOk   = U8 @(0xD0,0xB3,0xD0,0xBE,0xD1,0x82,0xD0,0xBE,0xD0,0xB2,0xD0,0xBE)
    StatusFail = U8 @(0xD0,0xBE,0xD1,0x88,0xD0,0xB8,0xD0,0xB1,0xD0,0xBA,0xD0,0xB0)
    Copied     = U8 @(0xD1,0x81,0xD0,0xBA,0xD0,0xBE,0xD0,0xBF,0xD0,0xB8,0xD1,0x80,0xD0,0xBE,0xD0,0xB2,0xD0,0xB0,0xD0,0xBD,0xD0,0xBE)
    ToastTitle = U8 @(0xD0,0x9F,0xD0,0xB5,0xD1,0x80,0xD0,0xB5,0xD0,0xB2,0xD0,0xBE,0xD0,0xB4)
    # "Select text or Ctrl+C, then say translate again."
    ToastEmpty = U8 @(0xD0,0x92,0xD1,0x8B,0xD0,0xB4,0xD0,0xB5,0xD0,0xBB,0xD0,0xB8,0x20,0xD1,0x82,0xD0,0xB5,0xD0,0xBA,0xD1,0x81,0xD1,0x82,0x20,0xD0,0xB8,0xD0,0xBB,0xD0,0xB8,0x20,0x43,0x74,0x72,0x6C,0x2B,0x43,0x2C,0x20,0xD0,0xBF,0xD0,0xBE,0xD1,0x82,0xD0,0xBE,0xD0,0xBC,0x20,0xD1,0x81,0xD0,0xBD,0xD0,0xBE,0xD0,0xB2,0xD0,0xB0,0x20,0xD0,0xBF,0xD0,0xB5,0xD1,0x80,0xD0,0xB5,0xD0,0xB2,0xD0,0xB5,0xD0,0xB4,0xD0,0xB8,0x2E)
    ErrNoKey   = U8 @(0xD0,0x9D,0xD0,0xB5,0xD1,0x82,0x20,0x41,0x50,0x49,0x2D,0xD0,0xBA,0xD0,0xBB,0xD1,0x8E,0xD1,0x87,0xD0,0xB0,0x2E,0x20,0xD0,0x9D,0xD0,0xB0,0xD1,0x81,0xD1,0x82,0xD1,0x80,0xD0,0xBE,0xD0,0xB9,0xD0,0xBA,0xD0,0xB8,0x20,0xE2,0x86,0x92,0x20,0xD0,0x9D,0xD0,0xB5,0xD0,0xB9,0xD1,0x80,0xD0,0xBE,0xD1,0x81,0xD0,0xB5,0xD1,0x82,0xD0,0xB8,0x2E)
    ErrSealed  = U8 @(0xD0,0x9A,0xD0,0xBB,0xD1,0x8E,0xD1,0x87,0x20,0xD0,0xBD,0xD0,0xB5,0x20,0xD1,0x87,0xD0,0xB8,0xD1,0x82,0xD0,0xB0,0xD0,0xB5,0xD1,0x82,0xD1,0x81,0xD1,0x8F,0x20,0xD0,0xBD,0xD0,0xB0,0x20,0xD1,0x8D,0xD1,0x82,0xD0,0xBE,0xD0,0xBC,0x20,0xD0,0x9F,0xD0,0x9A,0x2E,0x20,0xD0,0x92,0xD1,0x81,0xD1,0x82,0xD0,0xB0,0xD0,0xB2,0xD1,0x8C,0x20,0xD0,0xB7,0xD0,0xB0,0xD0,0xBD,0xD0,0xBE,0xD0,0xB2,0xD0,0xBE,0x20,0xD0,0xB2,0x20,0xD0,0x9D,0xD0,0xB0,0xD1,0x81,0xD1,0x82,0xD1,0x80,0xD0,0xBE,0xD0,0xB9,0xD0,0xBA,0xD0,0xB0,0xD1,0x85,0x2E)
}

$sourceText = Get-SelectionOrClipboard $Text
if ([string]::IsNullOrWhiteSpace($sourceText)) {
    $sourceText = Get-SelectionOrClipboard ""
}
if ([string]::IsNullOrWhiteSpace($sourceText)) {
    Show-JarvisToast $L.ToastTitle $L.ToastEmpty "warn"
    exit 0
}
if ($sourceText.Length -gt $MaxChars) {
    $sourceText = $sourceText.Substring(0, $MaxChars)
}

if ($CursorX -lt 0 -or $CursorY -lt 0) {
    $c = Get-CursorPosRaw
    $CursorX = $c.X
    $CursorY = $c.Y
}

$pair = Resolve-JarvisTranslatePair -Text $sourceText -Target $TargetLang
$routeLabel = ($pair -replace "\|", "  >  ").ToUpperInvariant()

$A = $hud.Accent
$AM = $hud.TextMuted
$AI = $hud.PanelInner
$AB = $hud.Border
$ABS = $hud.BorderSoft
$AP = $hud.PanelBg
$AH = $hud.HeaderBg
$AT = $hud.Text
$AD = $hud.AccentDimBg
$FU = $hud.FontUi
$FM = $hud.FontMono
$appearShared = Get-JarvisHudAppearStoryboardXaml
$btnTpl = Get-JarvisHudPrimaryButtonTemplate
$tplPrimary = Get-JarvisHud3dButtonTemplate -Top "#FF2A3355" -Mid "#FF1F2642" -Bot "#FF151B30" -TopHot "#FF3A4468" -BotHot "#FF1F2642" -Radius 8 -NamePrefix "ap"
$tplGhost = Get-JarvisHud3dButtonTemplate -Top "#FF3E4650" -Mid "#FF2E353F" -Bot "#FF1E232A" -TopHot "#FF4C5560" -BotHot "#FF2E353F" -Radius 8 -NamePrefix "ag"
$tplX = Get-JarvisHud3dButtonTemplate -Top "#FF2A3340" -Mid "#FF1D242E" -Bot "#FF141920" -TopHot "#FF3A4350" -BotHot "#FF1D242E" -Radius 8 -NamePrefix "ax"

$safeSrcLabel = Escape-JarvisHudText $L.TitleSrc
$safeDstLabel = Escape-JarvisHudText $L.TitleDst
$safeCopy = Escape-JarvisHudText $L.Copy
$safeClose = Escape-JarvisHudText $L.Close
$safeWait = Escape-JarvisHudText $L.StatusWait
$safeRoute = Escape-JarvisHudText $routeLabel

$xamlText = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="JARVIS TRANSLATE"
        Width="500" Height="440" MinWidth="420" MinHeight="340"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        ShowInTaskbar="False" Topmost="True" ResizeMode="CanResizeWithGrip" Opacity="0"
        ShowActivated="True" Cursor="Arrow">
  <Window.Resources>
$appearShared
    <Storyboard x:Key="RevealText">
      <DoubleAnimation Storyboard.TargetName="OutBlock" Storyboard.TargetProperty="Opacity" From="0" To="1" Duration="0:0:0.28"/>
      <DoubleAnimation Storyboard.TargetName="OutBlock" Storyboard.TargetProperty="(UIElement.RenderTransform).(TranslateTransform.Y)" From="8" To="0" Duration="0:0:0.28">
        <DoubleAnimation.EasingFunction><CubicEase EasingMode="EaseOut"/></DoubleAnimation.EasingFunction>
      </DoubleAnimation>
    </Storyboard>
  </Window.Resources>

  <Grid Margin="$($hud.GlowMargin)">
      <Border x:Name="GlowBorder" CornerRadius="$($hud.Corner)" Opacity="$($hud.GlowOpacity)" BorderBrush="$A" BorderThickness="2" IsHitTestVisible="False">
        <Border.Effect><BlurEffect Radius="$($hud.GlowBlur)"/></Border.Effect>
        <Border Background="$($hud.GlowFill)" CornerRadius="$($hud.Corner)"/>
      </Border>

      <Border x:Name="DragRoot" CornerRadius="$($hud.Corner)" BorderThickness="1.5" BorderBrush="$AB"
              Background="$AP" ClipToBounds="True" Cursor="Arrow">
        <Border.RenderTransform>
          <TransformGroup>
            <ScaleTransform x:Name="RootScale" ScaleX="0.88" ScaleY="0.88" CenterX="240" CenterY="200"/>
            <TranslateTransform x:Name="RootTranslate" Y="14"/>
          </TransformGroup>
        </Border.RenderTransform>

        <Grid>
          <Grid.RowDefinitions>
            <RowDefinition Height="48"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="58"/>
          </Grid.RowDefinitions>

          <Border x:Name="Header" Grid.Row="0" Background="$AH" Cursor="SizeAll" Padding="16,10,12,6" CornerRadius="14,14,0,0">
            <Grid>
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="Auto"/>
              </Grid.ColumnDefinitions>
              <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                <TextBlock Text="JARVIS" FontFamily="$FM" FontSize="14" FontWeight="Bold" Foreground="$A"/>
                <TextBlock Text="  //  TRANSLATE" FontFamily="$FM" FontSize="12" Foreground="$AM" Margin="2,1,0,0"/>
              </StackPanel>
              <Border Grid.Column="1" Background="$AD" BorderBrush="$A" BorderThickness="1" CornerRadius="4" Padding="10,3" Margin="0,0,10,0" VerticalAlignment="Center">
                <TextBlock x:Name="RouteText" Text="$safeRoute" FontFamily="$FM" FontSize="11" FontWeight="SemiBold" Foreground="$A"/>
              </Border>
              <Button x:Name="BtnX" Grid.Column="2" Content="X" Width="28" Height="28"
                      FontFamily="$FM" FontSize="12" FontWeight="Bold" Cursor="Hand"
                      Foreground="$AT" Background="#FF1D242E" BorderThickness="0" VerticalAlignment="Center">
$tplX
              </Button>
            </Grid>
          </Border>

          <Grid Grid.Row="1" Margin="14,4,14,4">
            <Border Background="$AI" BorderBrush="$ABS" BorderThickness="1" CornerRadius="10" Padding="14,12">
              <Grid>
                <Grid.RowDefinitions>
                  <RowDefinition Height="Auto"/>
                  <RowDefinition Height="*" MinHeight="72"/>
                  <RowDefinition Height="Auto"/>
                  <RowDefinition Height="Auto"/>
                  <RowDefinition Height="1.35*" MinHeight="96"/>
                </Grid.RowDefinitions>

                <TextBlock Grid.Row="0" Text="$safeSrcLabel" FontFamily="$FU" FontSize="10" FontWeight="SemiBold"
                           Foreground="$A" Opacity="0.9" Margin="2,0,2,6"/>

                <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled"
                              CanContentScroll="False" PanningMode="VerticalOnly" Margin="0,0,0,4"
                              Background="Transparent" Focusable="True">
                  <TextBlock x:Name="SrcText" TextWrapping="Wrap" Padding="2,0,8,4"
                             FontFamily="$FU" FontSize="14.5" FontWeight="Normal"
                             Foreground="$AT" LineHeight="21" TextOptions.TextFormattingMode="Display"/>
                </ScrollViewer>

                <Border Grid.Row="2" Height="1" Background="$ABS" Margin="0,8,0,10"/>

                <Grid Grid.Row="3" Margin="2,0,2,6">
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                  </Grid.ColumnDefinitions>
                  <TextBlock Text="$safeDstLabel" FontFamily="$FU" FontSize="10" FontWeight="SemiBold" Foreground="$A"/>
                  <TextBlock x:Name="StatusText" Grid.Column="1" Text="$safeWait" FontFamily="$FM"
                             FontSize="11" Foreground="$A"/>
                </Grid>

                <Border x:Name="OutBlock" Grid.Row="4" Opacity="0">
                  <Border.RenderTransform><TranslateTransform Y="8"/></Border.RenderTransform>
                  <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled"
                                CanContentScroll="False" PanningMode="VerticalOnly"
                                Background="Transparent" Focusable="True">
                    <TextBlock x:Name="DstText" TextWrapping="Wrap" Padding="2,0,8,4"
                               FontFamily="$FU" FontSize="16.5" FontWeight="SemiBold"
                               Foreground="$AT" LineHeight="24" TextOptions.TextFormattingMode="Display"/>
                  </ScrollViewer>
                </Border>
              </Grid>
            </Border>
          </Grid>

          <Grid Grid.Row="2" Margin="14,0,14,12">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/><ColumnDefinition Width="10"/>
              <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>

            <Button x:Name="BtnCopy" Grid.Column="0" Content="$safeCopy" Cursor="Hand" Height="36"
                    FontFamily="$FU" FontSize="13" FontWeight="SemiBold" Foreground="$AT"
                    Background="$($hud.BtnGhost)" BorderThickness="0">
$tplGhost
            </Button>

            <Button x:Name="BtnClose" Grid.Column="2" Content="$safeClose" Cursor="Hand" Height="36"
                    FontFamily="$FU" FontSize="13" FontWeight="SemiBold" Foreground="#FFFFFFFF"
                    Background="$($hud.BtnMatte)" BorderThickness="0" IsCancel="True">
$tplPrimary
            </Button>
          </Grid>
        </Grid>
      </Border>
  </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader ([xml]$xamlText)
$window = [Windows.Markup.XamlReader]::Load($reader)

$srcTb = $window.FindName("SrcText")
$dstTb = $window.FindName("DstText")
$stTb = $window.FindName("StatusText")
$outBlock = $window.FindName("OutBlock")
$btnCopy = $window.FindName("BtnCopy")
$btnClose = $window.FindName("BtnClose")
$btnX = $window.FindName("BtnX")
$routeTb = $window.FindName("RouteText")
$header = $window.FindName("Header")

$srcTb.Text = $sourceText
$routeTb.Text = $routeLabel

$window.WindowStartupLocation = "Manual"
$cx = $CursorX
$cy = $CursorY
$window.Add_SourceInitialized({
    $helper = New-Object System.Windows.Interop.WindowInteropHelper($window)
    $hwnd = $helper.EnsureHandle()
    $src = [System.Windows.Interop.HwndSource]::FromHwnd($hwnd)
    $fromDevice = $src.CompositionTarget.TransformFromDevice
    $dip = $fromDevice.Transform((New-Object System.Windows.Point $cx, $cy))

    $waPx = [System.Windows.Forms.Screen]::FromPoint((New-Object System.Drawing.Point $cx, $cy)).WorkingArea
    $waTL = $fromDevice.Transform((New-Object System.Windows.Point $waPx.Left, $waPx.Top))
    $waBR = $fromDevice.Transform((New-Object System.Windows.Point ($waPx.Right), ($waPx.Bottom)))

    $ww = $window.Width
    $wh = $window.Height
    $left = $dip.X + 18
    $top = $dip.Y + 18
    if (($left + $ww) -gt $waBR.X) { $left = $dip.X - $ww - 18 }
    if (($top + $wh) -gt $waBR.Y) { $top = $dip.Y - $wh - 18 }
    if ($left -lt $waTL.X) { $left = $waTL.X + 8 }
    if ($top -lt $waTL.Y) { $top = $waTL.Y + 8 }

    $window.Left = $left
    $window.Top = $top
})

$header.Add_MouseLeftButtonDown({
    param($s, $e)
    if ($e.OriginalSource -is [System.Windows.Controls.Button]) { return }
    if ($e.LeftButton -eq "Pressed") {
        try { $window.DragMove() } catch {}
    }
})

$appear = $window.Resources["Appear"]
$pulse = $window.Resources["Pulse"]
$dismiss = $window.Resources["Dismiss"]
$reveal = $window.Resources["RevealText"]

$script:closed = $false
$script:autoLeft = [int]$AutoCloseSec
function Reset-AutoClose {
    $script:autoLeft = [int]$AutoCloseSec
}
function Request-Close {
    if ($script:closed) { return }
    $script:closed = $true
    try { $autoTimer.Stop() } catch {}
    try {
        if ($null -ne $dismiss) { $dismiss.Begin($window) }
    } catch {}
    $kill = New-Object System.Windows.Threading.DispatcherTimer
    $kill.Interval = [TimeSpan]::FromMilliseconds([Math]::Max(160, [int]$hud.FadeMs + 40))
    $kill.Add_Tick({
        $kill.Stop()
        try { $window.Close() } catch {}
        try { [System.Windows.Application]::Current.Shutdown() } catch {}
        [Environment]::Exit(0)
    })
    $kill.Start()
}

Set-JarvisHudOverlayStyle -Window $window -StealFocus

$window.Add_ContentRendered({
    Set-JarvisHudOverlayStyle -Window $window -StealFocus
    try { $window.Topmost = $true } catch {}
    try { $window.Activate() } catch {}
    $appear.Begin($window)
    $pulse.Begin($window)
})

$sync = [hashtable]::Synchronized(@{
    Window = $window
    Dst = $dstTb
    St = $stTb
    Rev = $reveal
    Src = $sourceText
    Target = $TargetLang
    MaxChars = $MaxChars
    Result = $null
    Error = $null
    Accent = $hud.Accent
    Danger = $hud.Danger
    Ok = $hud.Ok
    StatusOk = $L.StatusOk
    StatusFail = $L.StatusFail
    ErrNoKey = $L.ErrNoKey
    ErrSealed = $L.ErrSealed
    ScriptRoot = $PSScriptRoot
})

$btnCopy.Add_Click({
    Reset-AutoClose
    if ($sync.Result) {
        try {
            [System.Windows.Forms.Clipboard]::SetText([string]$sync.Result)
            $stTb.Text = $L.Copied
            $stTb.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString($hud.Ok)
        } catch {}
    }
})
$btnClose.Add_Click({ Request-Close })
$btnX.Add_Click({ Request-Close })
$window.Add_KeyDown({
    param($s, $e)
    if ($e.Key -eq "Escape") { Request-Close }
    else { Reset-AutoClose }
})
$window.Add_MouseMove({ Reset-AutoClose })

$autoTimer = New-Object System.Windows.Threading.DispatcherTimer
$autoTimer.Interval = [TimeSpan]::FromSeconds(1)
$autoTimer.Add_Tick({
    $script:autoLeft--
    if ($script:autoLeft -le 0) { Request-Close }
})
$autoTimer.Start()

$rs = [runspacefactory]::CreateRunspace()
$rs.ApartmentState = "MTA"
$rs.Open()
$psWorker = [powershell]::Create()
$psWorker.Runspace = $rs
[void]$psWorker.AddScript({
    param($sync)
    Start-Sleep -Milliseconds 280
    try {
        . (Join-Path $sync.ScriptRoot "_jarvis-llm.ps1")
        . (Join-Path $sync.ScriptRoot "_jarvis-translate.ps1")

        $tr = Invoke-JarvisTranslateText -Text $sync.Src -Target $sync.Target -MaxChars $sync.MaxChars
        if (-not $tr.Ok) {
            $err = [string]$tr.Error
            if ($err -eq "NO_KEY" -or $err -eq "NO_SETTINGS") { $err = $sync.ErrNoKey }
            elseif ($err -eq "KEY_SEALED") { $err = $sync.ErrSealed }
            throw $err
        }
        $sync.Result = [string]$tr.Text
        $sync.Window.Dispatcher.Invoke([Action]{
            $sync.Dst.Text = $sync.Result
            $sync.St.Text = $sync.StatusOk
            $sync.St.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString($sync.Ok)
            $sync.Rev.Begin($sync.Window)
        }) | Out-Null
    } catch {
        $sync.Error = $_.Exception.Message
        $sync.Window.Dispatcher.Invoke([Action]{
            $sync.St.Text = $sync.StatusFail
            $sync.St.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString($sync.Danger)
            $sync.Dst.Text = $sync.Error
            $sync.Rev.Begin($sync.Window)
        }) | Out-Null
    }
}).AddArgument($sync)

$handle = $psWorker.BeginInvoke()
$window.Add_Closed({
    try {
        if ($handle -and -not $handle.IsCompleted) { $null = $psWorker.BeginStop($null, $null) }
        $psWorker.Dispose()
        $rs.Close(); $rs.Dispose()
    } catch {}
    try { $autoTimer.Stop() } catch {}
})

$window.ShowActivated = $true
$window.Topmost = $true
Set-JarvisHudOverlayStyle -Window $window -StealFocus
# If Appear storyboard never runs, force visible — otherwise Opacity stays 0.
$safety = New-Object System.Windows.Threading.DispatcherTimer
$safety.Interval = [TimeSpan]::FromMilliseconds(500)
$safety.Add_Tick({
    $safety.Stop()
    try {
        if ($window.Opacity -lt 0.2) { $window.Opacity = 1.0 }
    } catch {}
})
$safety.Start()
try { $window.Activate(); $btnClose.Focus() } catch {}
Set-JarvisHudOverlayStyle -Window $window -StealFocus
# ShowDialog (like toast.ps1) — reliable message pump on customer PCs.
[void]$window.ShowDialog()
try { [System.Windows.Application]::Current.Shutdown() } catch {}
exit 0
} catch {
    $msg = $_.Exception.Message
    if ([string]::IsNullOrWhiteSpace($msg)) { $msg = "$_" }
    try { Show-JarvisToast $L.ToastTitle $msg "error" } catch {
        try { Show-JarvisToast "JARVIS" $msg "error" } catch {}
    }
    exit 1
}
