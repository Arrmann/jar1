param(
    [string]$Text = "",
    [string]$TextFile = "",
    [ValidateSet("TIMER", "REMINDER")]
    [string]$Kind = "REMINDER",
    [int]$AutoCloseSec = 10
)

# ASCII-only source. Cyrillic via UTF-8 byte literals (WinPS 5.1 safe).
$ErrorActionPreference = "Stop"

function U8([byte[]]$b) { return [Text.Encoding]::UTF8.GetString($b) }

$L = @{
    Fallback   = U8 @(0xD0,0x9D,0xD0,0xB0,0xD0,0xBF,0xD0,0xBE,0xD0,0xBC,0xD0,0xB8,0xD0,0xBD,0xD0,0xB0,0xD0,0xBD,0xD0,0xB8,0xD0,0xB5) # Reminder
    Timer      = U8 @(0xD0,0xA2,0xD0,0x90,0xD0,0x99,0xD0,0x9C,0xD0,0x95,0xD0,0xA0) # TIMER
    Reminder   = U8 @(0xD0,0x9D,0xD0,0x90,0xD0,0x9F,0xD0,0x9E,0xD0,0x9C,0xD0,0x98,0xD0,0x9D,0xD0,0x90,0xD0,0x9D,0xD0,0x98,0xD0,0x95) # REMINDER
    Close      = U8 @(0xD0,0x97,0xD0,0x90,0xD0,0x9A,0xD0,0xA0,0xD0,0xAB,0xD0,0xA2,0xD0,0xAC) # CLOSE
}

if ($TextFile -and (Test-Path -LiteralPath $TextFile)) {
    $Text = [IO.File]::ReadAllText($TextFile, [Text.UTF8Encoding]::new($false)).Trim()
    try { Remove-Item -LiteralPath $TextFile -Force -ErrorAction SilentlyContinue } catch {}
}
if ([string]::IsNullOrWhiteSpace($Text)) {
    $Text = $L.Fallback
}

# Repair classic CP1251-as-UTF8 mojibake / replacement chars
if ($Text -match '[\u00C0-\u00FF]{3,}' -or $Text -match '\uFFFD') {
    try {
        $bytes = [Text.Encoding]::GetEncoding(1251).GetBytes($Text)
        $fixed = [Text.Encoding]::UTF8.GetString($bytes)
        # Cyrillic block via \u (ASCII-only source for WinPS 5.1)
        if ($fixed -match '[\u0400-\u04FF]') { $Text = $fixed }
    } catch {}
}

# Play alert audio BEFORE HUD chrome so notify still works if window fails.
$soundScript = Join-Path $PSScriptRoot "reminder-sound.ps1"
if (Test-Path -LiteralPath $soundScript) {
    try {
        & $soundScript -Kind $Kind
    } catch {
        try { [System.Media.SystemSounds]::Asterisk.Play() } catch {}
    }
} else {
    try {
        [console]::Beep(880, 120)
        Start-Sleep -Milliseconds 40
        [console]::Beep(1175, 160)
    } catch {
        try { [System.Media.SystemSounds]::Asterisk.Play() } catch {}
    }
}

. (Join-Path $PSScriptRoot "jarvis-hud-theme.ps1")
Ensure-JarvisHudAssemblies
$t = Get-JarvisHudTheme

$title = if ($Kind -eq "TIMER") { $L.Timer } else { $L.Reminder }
$accent = $t.Accent
$safeText = Escape-JarvisHudText $Text
$safeTitle = Escape-JarvisHudText $title
$safeClose = Escape-JarvisHudText $L.Close
$appearSb = Get-JarvisHudAppearStoryboardXaml
$btnTpl = Get-JarvisHudPrimaryButtonTemplate

$xamlText = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="JARVIS REMINDER"
        Width="460" Height="250"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        ShowInTaskbar="True" Topmost="True" ResizeMode="NoResize" Opacity="0"
        ShowActivated="True" WindowStartupLocation="Manual">
  <Window.Resources>
$appearSb
  </Window.Resources>

  <Grid Margin="$($t.GlowMargin)">
    <Border x:Name="GlowBorder" CornerRadius="$($t.Corner)" BorderBrush="$accent" BorderThickness="2"
            Opacity="$($t.GlowOpacity)" IsHitTestVisible="False">
      <Border.Effect><BlurEffect Radius="$($t.GlowBlur)"/></Border.Effect>
      <Border Background="$($t.GlowFill)" CornerRadius="$($t.Corner)"/>
    </Border>

    <Border CornerRadius="$($t.Corner)" BorderBrush="$($t.Border)" BorderThickness="1.5"
            Background="$($t.PanelBg)" Cursor="SizeAll">
      <Border.RenderTransform>
        <TransformGroup>
          <ScaleTransform x:Name="RootScale" ScaleX="0.88" ScaleY="0.88" CenterX="220" CenterY="110"/>
          <TranslateTransform x:Name="RootTranslate" Y="14"/>
        </TransformGroup>
      </Border.RenderTransform>
      <Grid>
        <Grid.RowDefinitions>
          <RowDefinition Height="48"/>
          <RowDefinition Height="*"/>
          <RowDefinition Height="58"/>
        </Grid.RowDefinitions>

        <Border Grid.Row="0" Background="$($t.HeaderBg)" Padding="18,12,18,8" x:Name="Header" CornerRadius="14,14,0,0">
          <Grid>
            <StackPanel Orientation="Horizontal" VerticalAlignment="Center" Margin="0,0,48,0">
              <TextBlock Text="JARVIS" FontFamily="$($t.FontMono)" FontSize="14" FontWeight="Bold" Foreground="$accent"/>
              <TextBlock Text="  //  $safeTitle" FontFamily="$($t.FontMono)" FontSize="12" Foreground="$($t.TextMuted)" Margin="2,1,0,0"/>
            </StackPanel>
            <TextBlock x:Name="Countdown" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,40,0"
                       FontFamily="$($t.FontMono)" FontSize="12" Foreground="$($t.TextFaint)" Text="${AutoCloseSec}s"/>
            <Button x:Name="BtnX" Content="X" HorizontalAlignment="Right" VerticalAlignment="Center"
                    Width="28" Height="28" FontFamily="$($t.FontMono)" FontSize="12" FontWeight="Bold"
                    Foreground="$($t.Text)" Background="#33FFFFFF" BorderBrush="$($t.BorderSoft)"
                    BorderThickness="1" Cursor="Hand">
$btnTpl
            </Button>
          </Grid>
        </Border>

        <Border Grid.Row="1" Margin="16,4,16,4" Background="$($t.PanelInner)" BorderBrush="$($t.BorderSoft)"
                BorderThickness="1" CornerRadius="$($t.CornerSm)" Padding="16,14">
          <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
            <TextBlock Text="$safeText" TextWrapping="Wrap" FontFamily="$($t.FontUi)"
                       FontSize="16.5" Foreground="$($t.Text)" LineHeight="24"/>
          </ScrollViewer>
        </Border>

        <Button x:Name="BtnClose" Grid.Row="2" Content="$safeClose" Margin="16,0,16,14" Height="36" Cursor="Hand"
                IsCancel="True" FontFamily="$($t.FontUi)" FontSize="13" FontWeight="SemiBold"
                Foreground="$($t.AccentDarkFg)" Background="$accent" BorderThickness="0">
$btnTpl
        </Button>
      </Grid>
    </Border>
  </Grid>
</Window>
"@

$window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$xamlText)))
$btn = $window.FindName("BtnClose")
$btnX = $window.FindName("BtnX")
$cd = $window.FindName("Countdown")
$header = $window.FindName("Header")

$script:closed = $false
function Request-Close {
    if ($script:closed) { return }
    $script:closed = $true
    try { $timer.Stop() } catch {}
    try { $window.Close() } catch {}
    $kill = New-Object System.Windows.Threading.DispatcherTimer
    $kill.Interval = [TimeSpan]::FromMilliseconds(500)
    $kill.Add_Tick({
        $kill.Stop()
        try { [System.Windows.Application]::Current.Shutdown() } catch {}
        [Environment]::Exit(0)
    })
    $kill.Start()
}

$header.Add_MouseLeftButtonDown({
    param($s, $e)
    if ($e.OriginalSource -is [System.Windows.Controls.Button]) { return }
    if ($e.LeftButton -eq "Pressed") { try { $window.DragMove() } catch {} }
})
$btn.Add_Click({ Request-Close })
$btnX.Add_Click({ Request-Close })
$window.Add_KeyDown({
    param($s, $e)
    if ($e.Key -eq "Escape") { Request-Close }
})

$appear = $window.Resources["Appear"]
$pulse = $window.Resources["Pulse"]
$window.Add_ContentRendered({
    $appear.Begin($window)
    $pulse.Begin($window)
})

$script:left = [int]$AutoCloseSec
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(1)
$timer.Add_Tick({
    $script:left--
    if ($script:left -le 0) { Request-Close }
    else { $cd.Text = ("{0}s" -f $script:left) }
})
$timer.Start()
$window.Add_Closed({ $timer.Stop() })

$window.ShowActivated = $true
$window.Topmost = $true
$window.WindowStartupLocation = "Manual"
Place-JarvisHudTopRight -Window $window

Set-JarvisHudOverlayStyle -Window $window -StealFocus
$window.Show()
try { $window.Activate(); $btn.Focus() } catch {}
Set-JarvisHudOverlayStyle -Window $window -StealFocus

$frame = New-Object System.Windows.Threading.DispatcherFrame
$window.Add_Closed({ $frame.Continue = $false })
[System.Windows.Threading.Dispatcher]::PushFrame($frame)
try { [System.Windows.Application]::Current.Shutdown() } catch {}
exit 0
