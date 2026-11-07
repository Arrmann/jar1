# Persistent REC indicator while screen recording is active.
$ErrorActionPreference = "SilentlyContinue"
. (Join-Path $PSScriptRoot "_jarvis-data-dir.ps1")
$dataDir = Get-JarvisDataDir
$activeFlag = Join-Path $dataDir "screen-record.active"
$hudPidFile = Join-Path $dataDir "screen-record.hud.pid"

if (-not (Test-Path -LiteralPath $activeFlag)) { exit 0 }

Set-Content -LiteralPath $hudPidFile -Value ([string]$PID) -Encoding ASCII

. (Join-Path $PSScriptRoot "jarvis-hud-theme.ps1")
Ensure-JarvisHudAssemblies
$t = Get-JarvisHudTheme

$startedAt = Get-Date
if (Test-Path -LiteralPath $activeFlag) {
    try {
        $raw = (Get-Content -LiteralPath $activeFlag -Raw -ErrorAction SilentlyContinue).Trim()
        if ($raw -match '^\d{4}-\d{2}-\d{2}T') {
            $startedAt = [DateTime]::Parse($raw)
        }
    } catch {}
}

$appearSb = Get-JarvisHudAppearStoryboardXaml

$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="JARVIS REC"
        Width="220" Height="52"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        ShowInTaskbar="False" Topmost="True" ResizeMode="NoResize" Opacity="0"
        ShowActivated="False" WindowStartupLocation="Manual">
  <Window.Resources>
$appearSb
  </Window.Resources>
  <Grid>
    <Border x:Name="GlowBorder" CornerRadius="12" Background="$($t.GlowFill)" Opacity="0.45" Margin="6"/>
    <Border CornerRadius="12" Background="$($t.PanelBg)" BorderBrush="$($t.DangerLine)" BorderThickness="1.5" Margin="8">
      <Grid Margin="14,8">
        <Grid.RenderTransform>
          <TransformGroup>
            <ScaleTransform x:Name="RootScale" ScaleX="1" ScaleY="1"/>
            <TranslateTransform x:Name="RootTranslate" Y="0"/>
          </TransformGroup>
        </Grid.RenderTransform>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>
        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
          <Ellipse x:Name="RecDot" Width="12" Height="12" Fill="$($t.Danger)" Margin="0,0,10,0"/>
          <TextBlock Text="REC" FontFamily="$($t.FontUi)" FontSize="15" FontWeight="Bold"
                     Foreground="$($t.DangerFg)" VerticalAlignment="Center"/>
        </StackPanel>
        <TextBlock x:Name="TimerText" Grid.Column="1" HorizontalAlignment="Right" VerticalAlignment="Center"
                   FontFamily="$($t.FontMono)" FontSize="14" Foreground="$($t.Text)" Text="00:00"/>
      </Grid>
    </Border>
  </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
$win = [Windows.Markup.XamlReader]::Load($reader)
Set-JarvisHudOverlayStyle -Window $win
$timerText = $win.FindName("TimerText")
$recDot = $win.FindName("RecDot")

$win.Add_Loaded({
    param($sender, $e)
    try {
        $wa = [System.Windows.SystemParameters]::WorkArea
        $w = $sender.Width
        $sender.Left = [Math]::Max(8, ($wa.Left + $wa.Width / 2) - ($w / 2))
        $sender.Top = [Math]::Max(8, $wa.Top + 10)
    } catch {}
    $appear = $sender.Resources["Appear"]
    if ($appear) { $appear.Begin($sender) | Out-Null }
    $pulse = $sender.Resources["Pulse"]
    if ($pulse) { $pulse.Begin($sender) | Out-Null }
})

$tick = New-Object System.Windows.Threading.DispatcherTimer
$tick.Interval = [TimeSpan]::FromMilliseconds(500)
$tick.Add_Tick({
    if (-not (Test-Path -LiteralPath $activeFlag)) {
        $tick.Stop()
        $win.Close()
        return
    }
    $elapsed = (Get-Date) - $startedAt
    if ($elapsed.TotalSeconds -lt 0) { $elapsed = [TimeSpan]::Zero }
    $timerText.Text = ("{0:mm\:ss}" -f $elapsed)
})
$tick.Start()

$win.Show()
[System.Windows.Threading.Dispatcher]::Run()
Remove-Item -LiteralPath $hudPidFile -Force -ErrorAction SilentlyContinue
exit 0
