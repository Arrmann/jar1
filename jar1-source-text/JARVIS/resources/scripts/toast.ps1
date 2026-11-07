param(
    [switch]$Ui,
    [string]$Title = "JARVIS",
    [string]$Message = "",
    [string]$TitleFile = "",
    [string]$MessageFile = "",
    [ValidateSet("info", "ok", "warn", "error")]
    [string]$Kind = "info",
    [int]$DurationMs = 2800
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_jarvis-hidden-process.ps1")

function Read-Utf8File([string]$path) {
    if (-not $path -or -not (Test-Path -LiteralPath $path)) { return $null }
    try {
        $t = [IO.File]::ReadAllText($path, [Text.UTF8Encoding]::new($false)).Trim()
        try { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue } catch {}
        if ([string]::IsNullOrWhiteSpace($t)) { return $null }
        return $t
    } catch { return $null }
}

$fromTitle = Read-Utf8File $TitleFile
$fromMsg = Read-Utf8File $MessageFile
if ($null -ne $fromTitle) { $Title = $fromTitle }
if ($null -ne $fromMsg) { $Message = $fromMsg }
if ([string]::IsNullOrWhiteSpace($Title)) { $Title = "JARVIS" }
if ($null -eq $Message) { $Message = "" }

# Detach UI so callers (jarvis-app) never block on WPF — unless already -Ui.
if (-not $Ui) {
    $argList = @(
        "-NoProfile", "-NonInteractive", "-STA", "-ExecutionPolicy", "Bypass",
        "-File", $PSCommandPath,
        "-Ui",
        "-Kind", $Kind,
        "-DurationMs", $DurationMs
    )
    $tmpTitle = Join-Path $env:TEMP ("jarvis-toast-t-" + [guid]::NewGuid().ToString("N") + ".txt")
    $tmpMsg = Join-Path $env:TEMP ("jarvis-toast-m-" + [guid]::NewGuid().ToString("N") + ".txt")
    [IO.File]::WriteAllText($tmpTitle, [string]$Title, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($tmpMsg, [string]$Message, [Text.UTF8Encoding]::new($false))
    $argList += @("-TitleFile", $tmpTitle, "-MessageFile", $tmpMsg)
    Start-JarvisHiddenProcess -FilePath "powershell.exe" -ArgumentList $argList | Out-Null
    exit 0
}

. (Join-Path $PSScriptRoot "jarvis-hud-theme.ps1")
Ensure-JarvisHudAssemblies
$t = Get-JarvisHudTheme

# Chrome accent ALWAYS cyan. Kind only in mono status label (+ optional muted chip tint).
$statusLabel = "INFO"
$chipFg = $t.Accent
switch ($Kind) {
    "ok"    { $statusLabel = "OK"; $chipFg = $t.Ok }
    "warn"  { $statusLabel = "WARN"; $chipFg = $t.Warn }
    "error" { $statusLabel = "ERR"; $chipFg = $t.Danger }
}

$appearSb = Get-JarvisHudAppearStoryboardXaml
$accent = $t.Accent

$xamlText = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="JARVIS"
        Width="420" Height="156" SizeToContent="Height"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        ShowInTaskbar="False" Topmost="True" ResizeMode="NoResize" Opacity="0"
        ShowActivated="False" WindowStartupLocation="Manual">
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
            Background="$($t.PanelBg)" Cursor="Arrow">
      <Border.RenderTransform>
        <TransformGroup>
          <ScaleTransform x:Name="RootScale" ScaleX="0.88" ScaleY="0.88" CenterX="200" CenterY="70"/>
          <TranslateTransform x:Name="RootTranslate" Y="14"/>
        </TransformGroup>
      </Border.RenderTransform>
      <Grid>
        <Grid.RowDefinitions>
          <RowDefinition Height="40"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <Border Grid.Row="0" Background="$($t.HeaderBg)" CornerRadius="14,14,0,0" Padding="14,8,14,6">
          <Grid>
            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
              <TextBlock Text="JARVIS" FontFamily="$($t.FontMono)" FontSize="14" FontWeight="Bold" Foreground="$accent"/>
              <TextBlock Text="  //  TOAST" FontFamily="$($t.FontMono)" FontSize="12" Foreground="$($t.TextMuted)" Margin="2,1,0,0"/>
            </StackPanel>
            <Border HorizontalAlignment="Right" Background="$($t.AccentDimBg)" BorderBrush="$accent" BorderThickness="1" CornerRadius="4" Padding="8,2">
              <TextBlock x:Name="StatusChip" Text="INFO" FontFamily="$($t.FontMono)" FontSize="11" FontWeight="SemiBold" Foreground="$accent"/>
            </Border>
          </Grid>
        </Border>

        <Border Grid.Row="1" Margin="12,8,12,12" Background="$($t.PanelInner)" BorderBrush="$($t.BorderSoft)"
                BorderThickness="1" CornerRadius="$($t.CornerSm)" Padding="12,10">
          <StackPanel>
            <TextBlock x:Name="TitleText" FontFamily="$($t.FontUi)" FontSize="12" FontWeight="SemiBold"
                       Foreground="$accent" Margin="0,0,0,6" TextTrimming="CharacterEllipsis"/>
            <TextBlock x:Name="MsgText" TextWrapping="Wrap" FontFamily="$($t.FontUi)"
                       FontSize="14.5" Foreground="$($t.Text)" LineHeight="21"/>
          </StackPanel>
        </Border>
      </Grid>
    </Border>
  </Grid>
</Window>
"@

$window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$xamlText)))
$titleTb = $window.FindName("TitleText")
$msgTb = $window.FindName("MsgText")
$statusChip = $window.FindName("StatusChip")
function Limit-JarvisHudString([string]$s, [int]$max) {
    if ($null -eq $s) { return "" }
    if ($s.Length -le $max) { return $s }
    if ($max -le 3) { return $s.Substring(0, $max) }
    return ($s.Substring(0, $max - 3) + "...")
}

$titleTb.Text = Limit-JarvisHudString ([string]$Title) 48
$msgTb.Text = Limit-JarvisHudString ([string]$Message) 280
$statusChip.Text = $statusLabel
$statusChip.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString($chipFg)

$window.ShowActivated = $false
$window.Topmost = $true

$appear = $window.Resources["Appear"]
$pulse = $window.Resources["Pulse"]
$dismiss = $window.Resources["Dismiss"]
$script:closing = $false

function Close-JarvisToastAnimated {
    if ($script:closing) { return }
    $script:closing = $true
    try { if ($null -ne $pulse) { $pulse.Stop($window) } } catch {}
    try { if ($null -ne $dismiss) { $dismiss.Begin($window) } } catch {}
    $script:toastFadeOut = New-Object System.Windows.Threading.DispatcherTimer
    $script:toastFadeOut.Interval = [TimeSpan]::FromMilliseconds(200)
    $script:toastFadeOut.Add_Tick({
        try { $script:toastFadeOut.Stop() } catch {}
        try { $window.Close() } catch {}
    })
    $script:toastFadeOut.Start()
}

$window.Add_ContentRendered({
    Place-JarvisHudTopRight -Window $window -MarginX 24 -MarginY 48
    Set-JarvisHudOverlayStyle -Window $window
    try { $appear.Begin($window); $pulse.Begin($window) } catch {}
})
$window.Add_MouseLeftButtonDown({ Close-JarvisToastAnimated })
$window.Add_KeyDown({
    param($s, $e)
    if ($e.Key -eq "Escape") { Close-JarvisToastAnimated }
})

$auto = New-Object System.Windows.Threading.DispatcherTimer
$auto.Interval = [TimeSpan]::FromMilliseconds([Math]::Max(800, $DurationMs))
$auto.Add_Tick({
    $auto.Stop()
    Close-JarvisToastAnimated
})
$auto.Start()
$window.Add_Closed({ $auto.Stop() })

# Keep ShowActivated false so games don't lose focus; ShowDialog still needed to pump messages.
$window.ShowActivated = $false
Set-JarvisHudOverlayStyle -Window $window
[void]$window.ShowDialog()
exit 0
