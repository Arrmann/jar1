param(
    [int]$AutoCloseSec = 0
)
# JARVIS timer list HUD - single window, inline edit, no InputBox / MessageBox.
# ASCII-only source. Cyrillic via UTF-8 byte literals (WinPS 5.1 safe).
$ErrorActionPreference = "Continue"
. (Join-Path $PSScriptRoot "_jarvis-hidden-process.ps1")

try {
    $mutex = [System.Threading.Mutex]::new($false, "Local\JarvisTimerListHud")
    if (-not $mutex.WaitOne(0)) {
        # Stale HUD often holds the mutex and new opens exit empty — reclaim once.
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
            $_.ProcessId -ne $PID -and $_.CommandLine -and ($_.CommandLine -match 'timer-list\.ps1')
        } | ForEach-Object {
            try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch {}
        }
        Start-Sleep -Milliseconds 250
        if (-not $mutex.WaitOne(0)) { exit 0 }
    }
} catch {}

. (Join-Path $PSScriptRoot "_jarvis-data-dir.ps1")
$StorePath = (Join-Path (Get-JarvisDataDir) "reminders.json")
$ScheduleScript = Join-Path $PSScriptRoot "schedule-reminder.ps1"
$Engine = Join-Path $PSScriptRoot "..\..\jarvis-app.exe"

. (Join-Path $PSScriptRoot "jarvis-hud-theme.ps1")
Ensure-JarvisHudAssemblies
$t = Get-JarvisHudTheme
$accent = $t.Accent
$tpl3dPrimaryXml = Get-JarvisHud3dButtonTemplateXaml -Top "#FF2A3355" -Mid "#FF1F2642" -Bot "#FF151B30" -TopHot "#FF3A4468" -BotHot "#FF1F2642" -Radius 8 -NamePrefix "p"
$tpl3dGhostXml = Get-JarvisHud3dButtonTemplateXaml -Top "#FF3E4650" -Mid "#FF2E353F" -Bot "#FF1E232A" -TopHot "#FF4C5560" -BotHot "#FF2E353F" -Radius 8 -NamePrefix "g"
$tpl3dInCardXml = Get-JarvisHud3dButtonTemplateXaml -Top "#FF4A5A7C" -Mid "#FF333F59" -Bot "#FF232B3E" -TopHot "#FF5A6A8C" -BotHot "#FF333F59" -Radius 8 -NamePrefix "i"
$tpl3dXXml = Get-JarvisHud3dButtonTemplateXaml -Top "#FF2A3340" -Mid "#FF1D242E" -Bot "#FF141920" -TopHot "#FF3A4350" -BotHot "#FF1D242E" -Radius 8 -NamePrefix "x"
function Wrap-JarvisBtnTpl([string]$xml, [string]$key) {
    return (($xml.Trim()) -replace '^<ControlTemplate TargetType="Button">', "<ControlTemplate x:Key=`"$key`" TargetType=`"Button`">")
}
$resPrimary = Wrap-JarvisBtnTpl $tpl3dPrimaryXml "Btn3dPrimary"
$resGhost = Wrap-JarvisBtnTpl $tpl3dGhostXml "Btn3dGhost"
$resInCard = Wrap-JarvisBtnTpl $tpl3dInCardXml "Btn3dInCard"
$resX = Wrap-JarvisBtnTpl $tpl3dXXml "Btn3dX"
$tplPrimary = Get-JarvisHud3dButtonTemplate -Top "#FF2A3355" -Mid "#FF1F2642" -Bot "#FF151B30" -TopHot "#FF3A4468" -BotHot "#FF1F2642" -Radius 8 -NamePrefix "ap"
$tplSecondary = Get-JarvisHud3dButtonTemplate -Top "#FF3E4650" -Mid "#FF2E353F" -Bot "#FF1E232A" -TopHot "#FF4C5560" -BotHot "#FF2E353F" -Radius 8 -NamePrefix "as"
$tplInCard = Get-JarvisHud3dButtonTemplate -Top "#FF4A5A7C" -Mid "#FF333F59" -Bot "#FF232B3E" -TopHot "#FF5A6A8C" -BotHot "#FF333F59" -Radius 8 -NamePrefix "ai"
$tplX = Get-JarvisHud3dButtonTemplate -Top "#FF2A3340" -Mid "#FF1D242E" -Bot "#FF141920" -TopHot "#FF3A4350" -BotHot "#FF1D242E" -Radius 8 -NamePrefix "ax"
$btnOn = $t.BtnOnMatte
$btnMatte = $t.BtnMatte
$btnGhost = $t.BtnGhost

function U8([byte[]]$b) { return [Text.Encoding]::UTF8.GetString($b) }

$L = @{
    Title      = U8 @(0x4A,0x41,0x52,0x56,0x49,0x53,0x20,0xE2,0x80,0x94,0x20,0xD0,0xA2,0xD0,0xB0,0xD0,0xB9,0xD0,0xBC,0xD0,0xB5,0xD1,0x80,0xD1,0x8B)
    PageTitle  = U8 @(0xD0,0xA2,0xD0,0xB0,0xD0,0xB9,0xD0,0xBC,0xD0,0xB5,0xD1,0x80,0xD1,0x8B)
    HeaderSub  = U8 @(0x20,0x20,0x2F,0x2F,0x20,0x20,0xD0,0x9C,0xD0,0x9E,0xD0,0x98,0x20,0xD0,0xA2,0xD0,0x90,0xD0,0x99,0xD0,0x9C,0xD0,0x95,0xD0,0xA0,0xD0,0xAB)
    CancelAll  = U8 @(0xD0,0x9E,0xD1,0x82,0xD0,0xBC,0xD0,0xB5,0xD0,0xBD,0xD0,0xB8,0xD1,0x82,0xD1,0x8C,0x20,0xD0,0xB2,0xD1,0x81,0xD0,0xB5)
    Close      = U8 @(0xD0,0x97,0xD0,0xB0,0xD0,0xBA,0xD1,0x80,0xD1,0x8B,0xD1,0x82,0xD1,0x8C)
    Timer      = U8 @(0xD0,0xA2,0xD0,0x90,0xD0,0x99,0xD0,0x9C,0xD0,0x95,0xD0,0xA0)
    Reminder   = U8 @(0xD0,0x9D,0xD0,0x90,0xD0,0x9F,0xD0,0x9E,0xD0,0x9C,0xD0,0x98,0xD0,0x9D,0xD0,0x90,0xD0,0x9D,0xD0,0x98,0xD0,0x95)
    Delete     = U8 @(0xD0,0xA3,0xD0,0x94,0xD0,0x90,0xD0,0x9B)
    Edit       = U8 @(0xD0,0x98,0xD0,0x97,0xD0,0x9C)
    EditTitle  = U8 @(0xD0,0x98,0xD0,0x97,0xD0,0x9C,0xD0,0x95,0xD0,0x9D,0xD0,0x98,0xD0,0xA2,0xD0,0xAC,0x20,0xD0,0xA2,0xD0,0x90,0xD0,0x99,0xD0,0x9C,0xD0,0x95,0xD0,0xA0)
    EditHint   = U8 @(0xD0,0x9D,0xD0,0xBE,0xD0,0xB2,0xD0,0xBE,0xD0,0xB5,0x20,0xD0,0xB2,0xD1,0x80,0xD0,0xB5,0xD0,0xBC,0xD1,0x8F,0x20,0x28,0x35,0x20,0xD0,0xBC,0xD0,0xB8,0xD0,0xBD,0x20,0x2F,0x20,0x33,0x30,0x20,0xD1,0x81,0xD0,0xB5,0xD0,0xBA,0x29)
    Save       = U8 @(0xD0,0xA1,0xD0,0x9E,0xD0,0xA5,0xD0,0xA0,0xD0,0x90,0xD0,0x9D,0xD0,0x98,0xD0,0xA2,0xD0,0xAC)
    Back       = U8 @(0xD0,0x9D,0xD0,0x90,0xD0,0x97,0xD0,0x90,0xD0,0x94)
    EditFail   = U8 @(0xD0,0x9D,0xD0,0xB5,0x20,0xD0,0xBF,0xD0,0xBE,0xD0,0xBD,0xD1,0x8F,0xD0,0xBB,0x20,0xD0,0xB2,0xD1,0x80,0xD0,0xB5,0xD0,0xBC,0xD1,0x8F)
    ToastEditOk= U8 @(0xD0,0xA2,0xD0,0xB0,0xD0,0xB9,0xD0,0xBC,0xD0,0xB5,0xD1,0x80,0x20,0xD0,0xBE,0xD0,0xB1,0xD0,0xBD,0xD0,0xBE,0xD0,0xB2,0xD0,0xBB,0xD1,0x91,0xD0,0xBD)
    EmptyBody  = U8 @(0xD0,0x9D,0xD0,0xB5,0xD1,0x82,0x20,0xD0,0xB0,0xD0,0xBA,0xD1,0x82,0xD0,0xB8,0xD0,0xB2,0xD0,0xBD,0xD1,0x8B,0xD1,0x85,0x20,0xD1,0x82,0xD0,0xB0,0xD0,0xB9,0xD0,0xBC,0xD0,0xB5,0xD1,0x80,0xD0,0xBE,0xD0,0xB2)
    EmptyHint  = U8 @(0x4A,0x41,0x52,0x56,0x49,0x53,0x20,0x20,0x2F,0x2F,0x20,0x20,0xD0,0x9F,0xD0,0xA3,0xD0,0xA1,0xD0,0xA2,0xD0,0x9E)
    ToastTitle = U8 @(0xD0,0xA2,0xD0,0xB0,0xD0,0xB9,0xD0,0xBC,0xD0,0xB5,0xD1,0x80,0xD1,0x8B)
    ToastOk    = U8 @(0xD0,0x92,0xD1,0x81,0xD0,0xB5,0x20,0xD0,0xBE,0xD1,0x82,0xD0,0xBC,0xD0,0xB5,0xD0,0xBD,0xD0,0xB5,0xD0,0xBD,0xD1,0x8B)
    Now        = U8 @(0xD1,0x81,0xD0,0xB5,0xD0,0xB9,0xD1,0x87,0xD0,0xB0,0xD1,0x81)
    Day        = U8 @(0xD0,0xB4)
    Hour       = U8 @(0xD1,0x87)
    Min        = U8 @(0xD0,0xBC)
    Sec        = U8 @(0xD1,0x81)
    Act        = U8 @(0x20,0xD0,0xB0,0xD0,0xBA,0xD1,0x82,0x2E)
    ViaPrefix  = U8 @(0xD1,0x87,0xD0,0xB5,0xD1,0x80,0xD0,0xB5,0xD0,0xB7,0x20)
    EditRx     = '(?i)\u0447\u0435\u0440\u0435\u0437|\u0442\u0430\u0439\u043c\u0435\u0440|\u043d\u0430\u043f\u043e\u043c\u043d\u0438'
    Presets    = @(
        @{ Label = U8 @(0x33,0x30,0xD1,0x81); Phrase = U8 @(0xD1,0x87,0xD0,0xB5,0xD1,0x80,0xD0,0xB5,0xD0,0xB7,0x20,0x33,0x30,0x20,0xD1,0x81,0xD0,0xB5,0xD0,0xBA) },
        @{ Label = U8 @(0x31,0xD0,0xBC); Phrase = U8 @(0xD1,0x87,0xD0,0xB5,0xD1,0x80,0xD0,0xB5,0xD0,0xB7,0x20,0x31,0x20,0xD0,0xBC,0xD0,0xB8,0xD0,0xBD) },
        @{ Label = U8 @(0x35,0xD0,0xBC); Phrase = U8 @(0xD1,0x87,0xD0,0xB5,0xD1,0x80,0xD0,0xB5,0xD0,0xB7,0x20,0x35,0x20,0xD0,0xBC,0xD0,0xB8,0xD0,0xBD) },
        @{ Label = U8 @(0x31,0x30,0xD0,0xBC); Phrase = U8 @(0xD1,0x87,0xD0,0xB5,0xD1,0x80,0xD0,0xB5,0xD0,0xB7,0x20,0x31,0x30,0x20,0xD0,0xBC,0xD0,0xB8,0xD0,0xBD) },
        @{ Label = U8 @(0x31,0x35,0xD0,0xBC); Phrase = U8 @(0xD1,0x87,0xD0,0xB5,0xD1,0x80,0xD0,0xB5,0xD0,0xB7,0x20,0x31,0x35,0x20,0xD0,0xBC,0xD0,0xB8,0xD0,0xBD) },
        @{ Label = U8 @(0x33,0x30,0xD0,0xBC); Phrase = U8 @(0xD1,0x87,0xD0,0xB5,0xD1,0x80,0xD0,0xB5,0xD0,0xB7,0x20,0x33,0x30,0x20,0xD0,0xBC,0xD0,0xB8,0xD0,0xBD) },
        @{ Label = U8 @(0x31,0xD1,0x87); Phrase = U8 @(0xD1,0x87,0xD0,0xB5,0xD1,0x80,0xD0,0xB5,0xD0,0xB7,0x20,0x31,0x20,0xD1,0x87,0xD0,0xB0,0xD1,0x81) }
    )
}

function Get-JarvisUnixNow {
    return [int64]([DateTime]::UtcNow - [datetime]'1970-01-01').TotalSeconds
}
function ConvertFrom-JarvisUnix([int64]$sec) {
    return ([datetime]'1970-01-01').AddSeconds($sec).ToLocalTime()
}
function Get-Pending {
    if (-not (Test-Path -LiteralPath $StorePath)) { return @() }
    try {
        $raw = [IO.File]::ReadAllBytes($StorePath)
        if ($raw.Length -ge 3 -and $raw[0] -eq 0xEF -and $raw[1] -eq 0xBB -and $raw[2] -eq 0xBF) {
            $raw = $raw[3..($raw.Length - 1)]
        }
        $obj = ([Text.Encoding]::UTF8.GetString($raw)) | ConvertFrom-Json
        if ($null -eq $obj.items) { return @() }
        $items = if ($obj.items -is [System.Array]) { @($obj.items) } else { @($obj.items) }
        $out = @()
        foreach ($it in $items) {
            if ($it.fired) { continue }
            $due = 0
            try { $due = [int64]$it.due_unix } catch { continue }
            if ($due -le 0) { continue }
            $label = [string]$it.text
            if ([string]::IsNullOrWhiteSpace($label)) { $label = [string]$it.label }
            $out += [pscustomobject]@{
                id        = [string]$it.id
                kind      = [string]$it.kind
                label     = $label
                due_unix  = $due
                due_local = (ConvertFrom-JarvisUnix $due)
            }
        }
        return @($out | Sort-Object due_unix)
    } catch { return @() }
}
function Format-Remaining([int64]$dueUnix) {
    $span = [TimeSpan]::FromSeconds([Math]::Max(0, $dueUnix - (Get-JarvisUnixNow)))
    if ($span.TotalSeconds -lt 1) { return $L.Now }
    $parts = @()
    if ($span.Days -gt 0) { $parts += ("{0}{1}" -f $span.Days, $L.Day) }
    if ($span.Hours -gt 0 -or $span.Days -gt 0) { $parts += ("{0}{1}" -f $span.Hours, $L.Hour) }
    if ($span.Minutes -gt 0 -or $span.Hours -gt 0 -or $span.Days -gt 0) { $parts += ("{0}{1}" -f $span.Minutes, $L.Min) }
    $parts += ("{0}{1}" -f $span.Seconds, $L.Sec)
    return ($parts -join " ")
}
function Cancel-One([string]$id) {
    if (Test-Path -LiteralPath $Engine) { & $Engine --schedule cancel_one --id $id | Out-Null; return $true }
    if (-not (Test-Path -LiteralPath $ScheduleScript)) { return $false }
    & powershell -NoProfile -STA -File $ScheduleScript -Action cancel_one -Id $id | Out-Null
    return $true
}
function Reschedule-One([string]$id, [string]$phrase) {
    if (-not (Test-Path -LiteralPath $Engine)) { return $false }
    $tf = Join-Path $env:TEMP ("jarvis-resched-" + [guid]::NewGuid().ToString("N") + ".txt")
    [IO.File]::WriteAllText($tf, [string]$phrase, [Text.UTF8Encoding]::new($false))
    $out = & $Engine --schedule reschedule --id $id --phrase-file $tf 2>&1 | Out-String
    return ($out -match 'OK:')
}
function Cancel-All {
    if (Test-Path -LiteralPath $Engine) { & $Engine --schedule cancel_all | Out-Null; return }
    if (-not (Test-Path -LiteralPath $ScheduleScript)) { return }
    Invoke-JarvisHiddenOutput -FilePath "powershell.exe" -ArgumentList @(
        "-NoProfile", "-STA", "-ExecutionPolicy", "Bypass", "-File", $ScheduleScript, "-Action", "cancel_all"
    ) | Out-Null
}
function Show-JarvisToast([string]$title, [string]$message, [string]$kind = "info") {
    $toast = Join-Path $PSScriptRoot "toast.ps1"
    if (-not (Test-Path -LiteralPath $toast)) { return }
    $tmpT = Join-Path $env:TEMP ("jarvis-toast-t-" + [guid]::NewGuid().ToString("N") + ".txt")
    $tmpM = Join-Path $env:TEMP ("jarvis-toast-m-" + [guid]::NewGuid().ToString("N") + ".txt")
    [IO.File]::WriteAllText($tmpT, [string]$title, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($tmpM, [string]$message, [Text.UTF8Encoding]::new($false))
    Start-JarvisHiddenProcess -FilePath "powershell.exe" -ArgumentList @(
        "-NoProfile", "-STA", "-ExecutionPolicy", "Bypass",
        "-File", $toast, "-Ui", "-TitleFile", $tmpT, "-MessageFile", $tmpM, "-Kind", $kind
    ) | Out-Null
}

$safeTitle = Escape-JarvisHudText $L.Title
$safePageTitle = Escape-JarvisHudText $L.PageTitle
$safeCancel = Escape-JarvisHudText $L.CancelAll
$safeClose = Escape-JarvisHudText $L.Close
$safeEditTitle = Escape-JarvisHudText $L.EditTitle
$safeEditHint = Escape-JarvisHudText $L.EditHint
$safeSave = Escape-JarvisHudText $L.Save
$safeBack = Escape-JarvisHudText $L.Back

# Appear without Opacity 0 start - transparent Opacity=0 windows eat clicks on some PCs.
$appearScaleOnly = @"
    <Storyboard x:Key="Appear">
      <DoubleAnimation Storyboard.TargetName="RootScale" Storyboard.TargetProperty="ScaleX"
                       From="0.97" To="1.0" Duration="0:0:0.22">
        <DoubleAnimation.EasingFunction><CubicEase EasingMode="EaseOut"/></DoubleAnimation.EasingFunction>
      </DoubleAnimation>
      <DoubleAnimation Storyboard.TargetName="RootScale" Storyboard.TargetProperty="ScaleY"
                       From="0.97" To="1.0" Duration="0:0:0.22">
        <DoubleAnimation.EasingFunction><CubicEase EasingMode="EaseOut"/></DoubleAnimation.EasingFunction>
      </DoubleAnimation>
      <DoubleAnimation Storyboard.TargetName="RootTranslate" Storyboard.TargetProperty="Y"
                       From="8" To="0" Duration="0:0:0.22">
        <DoubleAnimation.EasingFunction><CubicEase EasingMode="EaseOut"/></DoubleAnimation.EasingFunction>
      </DoubleAnimation>
    </Storyboard>
    <Storyboard x:Key="Shimmer" RepeatBehavior="Forever" AutoReverse="True">
      <PointAnimation Storyboard.TargetName="GlowA" Storyboard.TargetProperty="Center"
                      From="0.12,0.92" To="0.86,0.16" Duration="0:0:16">
        <PointAnimation.EasingFunction><SineEase EasingMode="EaseInOut"/></PointAnimation.EasingFunction>
      </PointAnimation>
      <PointAnimation Storyboard.TargetName="GlowA" Storyboard.TargetProperty="GradientOrigin"
                      From="0.12,0.92" To="0.86,0.16" Duration="0:0:16">
        <PointAnimation.EasingFunction><SineEase EasingMode="EaseInOut"/></PointAnimation.EasingFunction>
      </PointAnimation>
      <PointAnimation Storyboard.TargetName="GlowB" Storyboard.TargetProperty="Center"
                      From="0.88,0.10" To="0.14,0.88" Duration="0:0:18">
        <PointAnimation.EasingFunction><SineEase EasingMode="EaseInOut"/></PointAnimation.EasingFunction>
      </PointAnimation>
      <PointAnimation Storyboard.TargetName="GlowB" Storyboard.TargetProperty="GradientOrigin"
                      From="0.88,0.10" To="0.14,0.88" Duration="0:0:18">
        <PointAnimation.EasingFunction><SineEase EasingMode="EaseInOut"/></PointAnimation.EasingFunction>
      </PointAnimation>
      <DoubleAnimation Storyboard.TargetName="ShimmerA" Storyboard.TargetProperty="Opacity"
                       From="0.22" To="0.42" Duration="0:0:14">
        <DoubleAnimation.EasingFunction><SineEase EasingMode="EaseInOut"/></DoubleAnimation.EasingFunction>
      </DoubleAnimation>
      <DoubleAnimation Storyboard.TargetName="ShimmerB" Storyboard.TargetProperty="Opacity"
                       From="0.12" To="0.28" Duration="0:0:16">
        <DoubleAnimation.EasingFunction><SineEase EasingMode="EaseInOut"/></DoubleAnimation.EasingFunction>
      </DoubleAnimation>
      <ColorAnimation Storyboard.TargetName="GlowAStop0" Storyboard.TargetProperty="Color"
                      From="#335B4DFF" To="#2838A0C8" Duration="0:0:18">
        <ColorAnimation.EasingFunction><SineEase EasingMode="EaseInOut"/></ColorAnimation.EasingFunction>
      </ColorAnimation>
    </Storyboard>
$resPrimary
$resGhost
$resInCard
$resX
"@

$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$safeTitle"
        Width="560" Height="620"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        ShowInTaskbar="True" Topmost="True" ResizeMode="NoResize" Opacity="1"
        ShowActivated="True" WindowStartupLocation="CenterScreen">
  <Window.Resources>
$appearScaleOnly
  </Window.Resources>

  <Grid Margin="28">
    <Grid.RenderTransform>
      <TransformGroup>
        <ScaleTransform x:Name="RootScale" ScaleX="1" ScaleY="1" CenterX="252" CenterY="282"/>
        <TranslateTransform x:Name="RootTranslate" Y="0"/>
      </TransformGroup>
    </Grid.RenderTransform>

    <Border CornerRadius="26" Background="#E610141C">
      <Border.Effect>
        <DropShadowEffect Color="#000000" BlurRadius="64" ShadowDepth="6" Direction="270" Opacity="0.38"/>
      </Border.Effect>
    </Border>

    <Border x:Name="ShimmerA" CornerRadius="26" IsHitTestVisible="False" Opacity="0.32">
      <Border.Effect>
        <BlurEffect Radius="32"/>
      </Border.Effect>
      <Border.Background>
        <RadialGradientBrush x:Name="GlowA" Center="0.12,0.92" GradientOrigin="0.12,0.92" RadiusX="1.15" RadiusY="0.90">
          <GradientStop x:Name="GlowAStop0" Color="#335B4DFF" Offset="0"/>
          <GradientStop Color="#182A5A8A" Offset="0.55"/>
          <GradientStop Color="#00000000" Offset="1"/>
        </RadialGradientBrush>
      </Border.Background>
    </Border>
    <Border x:Name="ShimmerB" CornerRadius="26" IsHitTestVisible="False" Opacity="0.20">
      <Border.Effect>
        <BlurEffect Radius="28"/>
      </Border.Effect>
      <Border.Background>
        <RadialGradientBrush x:Name="GlowB" Center="0.88,0.10" GradientOrigin="0.88,0.10" RadiusX="1.05" RadiusY="0.80">
          <GradientStop Color="#223A7A9A" Offset="0"/>
          <GradientStop Color="#121E3A55" Offset="0.58"/>
          <GradientStop Color="#00000000" Offset="1"/>
        </RadialGradientBrush>
      </Border.Background>
    </Border>
    <Border CornerRadius="26" IsHitTestVisible="False">
      <Border.Background>
        <LinearGradientBrush StartPoint="0,0" EndPoint="0,0.38">
          <GradientStop Color="#14FFFFFF" Offset="0"/>
          <GradientStop Color="#00FFFFFF" Offset="1"/>
        </LinearGradientBrush>
      </Border.Background>
    </Border>

    <Border CornerRadius="26" BorderBrush="#22FFFFFF" BorderThickness="1" Background="Transparent">
      <Grid>
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <Border Grid.Row="0" Background="Transparent" CornerRadius="26,26,0,0" Padding="22,20,16,8" x:Name="Header" Cursor="SizeAll">
          <Grid>
            <StackPanel VerticalAlignment="Center" Margin="0,0,44,0">
              <TextBlock Text="$safePageTitle" FontFamily="Segoe UI" FontSize="22" FontWeight="Bold" Foreground="#FFFFFFFF"/>
              <TextBlock x:Name="CountLabel" FontFamily="Segoe UI" FontSize="13" Foreground="#FF94A3B8" Margin="0,4,0,0" Text=""/>
            </StackPanel>
            <Button x:Name="BtnX" Content="X" HorizontalAlignment="Right" VerticalAlignment="Top"
                    Width="32" Height="32" FontFamily="Segoe UI" FontSize="13" FontWeight="SemiBold"
                    Foreground="#FFFFFFFF" Background="$btnGhost" BorderThickness="0"
                    Cursor="Hand" Focusable="False" Padding="0"
                    Template="{StaticResource Btn3dX}"/>
          </Grid>
        </Border>

        <Grid Grid.Row="1">
          <ScrollViewer x:Name="ListScroll" VerticalScrollBarVisibility="Auto" Padding="16,10,16,14">
            <StackPanel x:Name="ListHost"/>
          </ScrollViewer>

          <Border x:Name="EditPanel" Visibility="Collapsed" Background="Transparent" Padding="16,8,16,8">
            <Grid>
              <Border CornerRadius="18" Background="#3A000000" Margin="2,8,2,-3" IsHitTestVisible="False">
                <Border.Effect>
                  <BlurEffect Radius="14"/>
                </Border.Effect>
              </Border>
              <Border Background="#E61A2230" BorderThickness="1" CornerRadius="16" Padding="18" Margin="0,0,0,8">
                <Border.BorderBrush>
                  <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
                    <GradientStop Color="#40FFFFFF" Offset="0"/>
                    <GradientStop Color="#14FFFFFF" Offset="1"/>
                  </LinearGradientBrush>
                </Border.BorderBrush>
                <Grid>
                  <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="Auto"/>
                  </Grid.RowDefinitions>
                  <TextBlock Grid.Row="0" Text="$safeEditTitle" FontFamily="Segoe UI" FontSize="16" FontWeight="Bold" Foreground="#FFFFFFFF"/>
                  <TextBlock x:Name="EditTarget" Grid.Row="1" Margin="0,6,0,0" TextWrapping="Wrap"
                             FontFamily="Segoe UI" FontSize="13" Foreground="#FF94A3B8"/>
                  <TextBlock Grid.Row="2" Margin="0,14,0,6" Text="$safeEditHint" FontFamily="Segoe UI" FontSize="12" Foreground="#FF94A3B8"/>
                  <Border Grid.Row="3" Height="40" CornerRadius="10"
                          Background="#FF0D1118" BorderBrush="#33FFFFFF" BorderThickness="1">
                    <Grid>
                      <TextBox x:Name="EditBox" Height="38" Padding="12,8"
                               FontFamily="Segoe UI" FontSize="14"
                               Background="Transparent" BorderThickness="0"
                               Foreground="Transparent" CaretBrush="#FFF2F5F8"
                               VerticalContentAlignment="Center"
                               HorizontalScrollBarVisibility="Hidden" VerticalScrollBarVisibility="Disabled"/>
                      <TextBlock x:Name="EditInk" IsHitTestVisible="False"
                                 FontFamily="Segoe UI" FontSize="14" Foreground="#FFF2F5F8"
                                 VerticalAlignment="Center" Margin="14,0,14,0"
                                 TextTrimming="CharacterEllipsis"/>
                    </Grid>
                  </Border>
                  <WrapPanel x:Name="PresetHost" Grid.Row="4" Margin="0,14,0,0"/>
                  <StackPanel Grid.Row="5" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,16,0,0">
                    <Button x:Name="BtnEditBack" Content="$safeBack" MinWidth="100" Height="34" Padding="14,0" Margin="0,0,8,0"
                            FontFamily="Segoe UI" FontSize="13" FontWeight="SemiBold"
                            Foreground="$btnOn" Background="$btnGhost" BorderThickness="0"
                            Cursor="Hand" Focusable="False" Template="{StaticResource Btn3dGhost}"/>
                    <Button x:Name="BtnEditSave" Content="$safeSave" MinWidth="120" Height="34" Padding="16,0"
                            FontFamily="Segoe UI" FontSize="13" FontWeight="SemiBold"
                            Foreground="$btnOn" Background="$btnMatte" BorderThickness="0"
                            Cursor="Hand" Template="{StaticResource Btn3dPrimary}"/>
                  </StackPanel>
                </Grid>
              </Border>
            </Grid>
          </Border>
        </Grid>

        <Border Grid.Row="2" Background="#990A0C19" CornerRadius="0,0,26,26" Padding="16,14,16,16">
          <Grid>
            <Button x:Name="BtnCancelAll" Content="$safeCancel" HorizontalAlignment="Left" MinWidth="156" Height="36" Padding="16,0"
                    FontFamily="Segoe UI" FontSize="13" FontWeight="SemiBold"
                    Foreground="$btnOn" Background="$btnGhost" BorderThickness="0"
                    Cursor="Hand" Focusable="False" Template="{StaticResource Btn3dGhost}"/>
            <Button x:Name="BtnClose" Content="$safeClose" HorizontalAlignment="Right" MinWidth="120" Height="36" Padding="16,0"
                    FontFamily="Segoe UI" FontSize="13" FontWeight="SemiBold"
                    Foreground="$btnOn" Background="$btnMatte" BorderThickness="0"
                    Cursor="Hand" Template="{StaticResource Btn3dPrimary}"/>
          </Grid>
        </Border>
      </Grid>
    </Border>
  </Grid>
</Window>
"@

$window = $null
try {
    $window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$xaml)))
} catch {
    try {
        [IO.File]::WriteAllText((Join-Path $env:TEMP "jarvis-timer-list-boot.err"), $_.Exception.ToString(), [Text.UTF8Encoding]::new($false))
    } catch {}
    [Environment]::Exit(1)
}
$header = $window.FindName("Header")
$listHost = $window.FindName("ListHost")
$countLabel = $window.FindName("CountLabel")
$btnClose = $window.FindName("BtnClose")
$btnX = $window.FindName("BtnX")
$btnCancelAll = $window.FindName("BtnCancelAll")
$editPanel = $window.FindName("EditPanel")
$listScroll = $window.FindName("ListScroll")
$editBox = $window.FindName("EditBox")
$editInk = $window.FindName("EditInk")
$editTarget = $window.FindName("EditTarget")
$presetHost = $window.FindName("PresetHost")
$btnEditBack = $window.FindName("BtnEditBack")
$btnEditSave = $window.FindName("BtnEditSave")
Set-JarvisHudMatteButton -Button $btnClose -Kind primary -Template $tplPrimary
Set-JarvisHudMatteButton -Button $btnCancelAll -Kind secondary -Template $tplSecondary
Set-JarvisHudMatteButton -Button $btnEditBack -Kind secondary -Template $tplSecondary
Set-JarvisHudMatteButton -Button $btnEditSave -Kind primary -Template $tplPrimary
Set-JarvisHudMatteButton -Button $btnX -Kind secondary -Template $tplX
Set-JarvisHudLayeredWindow $window
if ($null -ne $editBox) {
    Set-JarvisHudInputInk -Box $editBox -Ink $editInk
}

$script:closeRequested = $false
$script:editId = $null
$script:rowLeft = @{}
$script:rowDue = @{}
$script:lastIdsKey = ""
$script:editing = $false

function Request-Close {
    if ($script:closeRequested) { return }
    $script:closeRequested = $true
    try { if ($null -ne $script:tick) { $script:tick.Stop() } } catch {}
    try { if ($null -ne $script:auto) { $script:auto.Stop() } } catch {}
    try { $window.Hide() } catch {}
    try { $window.Close() } catch {}
    try { [System.Windows.Application]::Current.Shutdown() } catch {}
    [Environment]::Exit(0)
}

function Hide-Edit {
    $script:editing = $false
    $script:editId = $null
    $editPanel.Visibility = "Collapsed"
    $listScroll.Visibility = "Visible"
    $btnCancelAll.IsEnabled = $true
}

function Show-Edit([string]$id, [string]$label) {
    $script:editing = $true
    $script:editId = $id
    $editTarget.Text = $label
    $editBox.Text = ""
    $listScroll.Visibility = "Collapsed"
    $editPanel.Visibility = "Visible"
    $btnCancelAll.IsEnabled = $false
    try { $editBox.Focus(); $editBox.SelectAll() } catch {}
}

function Apply-Reschedule([string]$phrase) {
    if ([string]::IsNullOrWhiteSpace($script:editId)) { return }
    $p = $phrase.Trim()
    if ([string]::IsNullOrWhiteSpace($p)) { return }
    if ($p -notmatch $L.EditRx) { $p = $L.ViaPrefix + $p }
    if (Reschedule-One $script:editId $p) {
        Hide-Edit
        Refresh-List -Force
        Show-JarvisToast $L.ToastTitle $L.ToastEditOk "ok"
    } else {
        Show-JarvisToast $L.ToastTitle $L.EditFail "error"
    }
}

# Preset chips
foreach ($pr in $L.Presets) {
    $b = New-Object System.Windows.Controls.Button
    $b.Content = $pr.Label
    $b.MinWidth = 56
    $b.Height = 30
    $b.Padding = [System.Windows.Thickness]::new(12, 0, 12, 0)
    $b.Margin = [System.Windows.Thickness]::new(0, 0, 8, 8)
    $b.FontSize = 13
    $b.Tag = $pr.Phrase
    Set-JarvisHudMatteButton -Button $b -Kind secondary -Template $tplSecondary
    $b.Add_Click({
        param($s, $e)
        Apply-Reschedule ([string]$s.Tag)
    })
    [void]$presetHost.Children.Add($b)
}

$header.Add_MouseLeftButtonDown({
    param($s, $e)
    try {
        if ($e.OriginalSource -is [System.Windows.Controls.Button]) { return }
        if ($e.LeftButton -eq "Pressed") { $window.DragMove() }
    } catch {}
})
$btnClose.Add_Click({ try { Request-Close } catch { [Environment]::Exit(0) } })
$btnX.Add_Click({ try { Request-Close } catch { [Environment]::Exit(0) } })
$window.Add_KeyDown({
    param($s, $e)
    try {
        if ($e.Key -eq "Escape") {
            if ($script:editing) { Hide-Edit } else { Request-Close }
        }
        elseif ($e.Key -eq "Return" -and $script:editing) {
            Apply-Reschedule $editBox.Text
        }
    } catch { [Environment]::Exit(0) }
})
$btnEditBack.Add_Click({ Hide-Edit })
$btnEditSave.Add_Click({ Apply-Reschedule $editBox.Text })
$btnCancelAll.Add_Click({
    try {
        Cancel-All
        Hide-Edit
        Refresh-List -Force
        Show-JarvisToast $L.ToastTitle $L.ToastOk "ok"
    } catch {}
})

$appear = $window.Resources["Appear"]
$shimmer = $window.Resources["Shimmer"]
$window.Add_ContentRendered({
    try { $appear.Begin($window) } catch {}
    try { $shimmer.Begin($window) } catch {}
})

function New-Row($item) {
    $id = [string]$item.id
    $kind = if ($item.kind -eq "reminder") { $L.Reminder } else { $L.Timer }
    $label = [string]$item.label
    if ([string]::IsNullOrWhiteSpace($label)) { $label = $kind }
    $left = Format-Remaining ([int64]$item.due_unix)
    $when = $item.due_local.ToString("dd.MM HH:mm:ss")

    $wrap = New-Object System.Windows.Controls.Grid
    $wrap.Margin = [System.Windows.Thickness]::new(0, 0, 0, 14)

    $shade = New-Object System.Windows.Controls.Border
    $shade.CornerRadius = [System.Windows.CornerRadius]::new(18)
    $shade.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#3A000000")
    $shade.Margin = [System.Windows.Thickness]::new(2, 8, 2, -3)
    $shade.IsHitTestVisible = $false
    $shadeBlur = New-Object System.Windows.Media.Effects.BlurEffect
    $shadeBlur.Radius = 14
    $shade.Effect = $shadeBlur

    $row = New-Object System.Windows.Controls.Border
    $row.Padding = [System.Windows.Thickness]::new(16, 14, 16, 14)
    $row.CornerRadius = [System.Windows.CornerRadius]::new(16)
    $row.BorderThickness = [System.Windows.Thickness]::new(1)
    $row.Tag = $id
    $cardBg = New-Object System.Windows.Media.LinearGradientBrush
    $cardBg.StartPoint = [System.Windows.Point]::new(0, 0)
    $cardBg.EndPoint = [System.Windows.Point]::new(0, 1)
    $gs0 = New-Object System.Windows.Media.GradientStop
    $gs0.Color = [System.Windows.Media.Color]::FromArgb(0xEE, 0x1C, 0x25, 0x32); $gs0.Offset = 0
    $gs1 = New-Object System.Windows.Media.GradientStop
    $gs1.Color = [System.Windows.Media.Color]::FromArgb(0xEE, 0x12, 0x18, 0x22); $gs1.Offset = 1
    [void]$cardBg.GradientStops.Add($gs0)
    [void]$cardBg.GradientStops.Add($gs1)
    $row.Background = $cardBg
    $cardEdge = New-Object System.Windows.Media.LinearGradientBrush
    $cardEdge.StartPoint = [System.Windows.Point]::new(0, 0)
    $cardEdge.EndPoint = [System.Windows.Point]::new(0, 1)
    $ge0 = New-Object System.Windows.Media.GradientStop
    $ge0.Color = [System.Windows.Media.Color]::FromArgb(0x38, 0xFF, 0xFF, 0xFF); $ge0.Offset = 0
    $ge1 = New-Object System.Windows.Media.GradientStop
    $ge1.Color = [System.Windows.Media.Color]::FromArgb(0x12, 0xFF, 0xFF, 0xFF); $ge1.Offset = 1
    [void]$cardEdge.GradientStops.Add($ge0)
    [void]$cardEdge.GradientStops.Add($ge1)
    $row.BorderBrush = $cardEdge

    $g = New-Object System.Windows.Controls.Grid
    $c0 = New-Object System.Windows.Controls.ColumnDefinition; $c0.Width = [System.Windows.GridLength]::new(1, "Star")
    $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = [System.Windows.GridLength]::Auto
    [void]$g.ColumnDefinitions.Add($c0)
    [void]$g.ColumnDefinitions.Add($c1)

    $stack = New-Object System.Windows.Controls.StackPanel

    $tbKind = New-Object System.Windows.Controls.TextBlock
    $tbKind.Text = ("{0}  ·  {1}" -f $kind, $when)
    $tbKind.FontFamily = [System.Windows.Media.FontFamily]::new("Segoe UI")
    $tbKind.FontSize = 12
    $tbKind.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FF94A3B8")
    $tbLabel = New-Object System.Windows.Controls.TextBlock
    $tbLabel.Text = $label
    $tbLabel.FontFamily = [System.Windows.Media.FontFamily]::new("Segoe UI")
    $tbLabel.FontSize = 14
    $tbLabel.FontWeight = "SemiBold"
    $tbLabel.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FFFFFFFF")
    $tbLabel.TextWrapping = "Wrap"
    $tbLabel.Margin = [System.Windows.Thickness]::new(0, 4, 8, 0)
    $tbLeft = New-Object System.Windows.Controls.TextBlock
    $tbLeft.Text = $left
    $tbLeft.FontFamily = [System.Windows.Media.FontFamily]::new("Segoe UI")
    $tbLeft.FontSize = 22
    $tbLeft.FontWeight = "Bold"
    $tbLeft.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FFFFFFFF")
    $tbLeft.Margin = [System.Windows.Thickness]::new(0, 8, 0, 0)
    [void]$stack.Children.Add($tbKind)
    [void]$stack.Children.Add($tbLabel)
    [void]$stack.Children.Add($tbLeft)
    [System.Windows.Controls.Grid]::SetColumn($stack, 0)
    [void]$g.Children.Add($stack)

    $btns = New-Object System.Windows.Controls.StackPanel
    $btns.Orientation = "Vertical"
    $btns.VerticalAlignment = "Center"
    $btns.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)

    $btnE = New-Object System.Windows.Controls.Button
    $btnE.Content = $L.Edit
    $btnE.Width = 72; $btnE.Height = 28
    $btnE.Margin = [System.Windows.Thickness]::new(0, 0, 0, 6)
    $btnE.FontSize = 12
    Set-JarvisHudMatteButton -Button $btnE -Kind incard -Template $tplInCard
    $btnE.Tag = @{ Id = $id; Label = $label }
    $btnE.Add_Click({
        param($s, $e)
        $tag = $s.Tag
        Show-Edit ([string]$tag.Id) ([string]$tag.Label)
    })

    $btnD = New-Object System.Windows.Controls.Button
    $btnD.Content = $L.Delete
    $btnD.Width = 72; $btnD.Height = 28
    $btnD.FontSize = 12
    Set-JarvisHudMatteButton -Button $btnD -Kind secondary -Template $tplSecondary
    $btnD.Tag = $id
    $btnD.Add_Click({
        param($s, $e)
        Cancel-One ([string]$s.Tag) | Out-Null
        Refresh-List -Force
    })

    [void]$btns.Children.Add($btnE)
    [void]$btns.Children.Add($btnD)
    [System.Windows.Controls.Grid]::SetColumn($btns, 1)
    [void]$g.Children.Add($btns)
    $row.Child = $g
    [void]$wrap.Children.Add($shade)
    [void]$wrap.Children.Add($row)

    $script:rowLeft[$id] = $tbLeft
    $script:rowDue[$id] = [int64]$item.due_unix
    return $wrap
}

function Refresh-List {
    param([switch]$Force)
    if ($script:editing -and -not $Force) {
        # keep countdown labels updating under edit? skip list rebuild
        foreach ($k in @($script:rowLeft.Keys)) {
            try {
                $due = [int64]$script:rowDue[$k]
                $script:rowLeft[$k].Text = (Format-Remaining $due)
            } catch {}
        }
        return
    }
    try {
        $items = @(Get-Pending)
        $idsKey = (($items | ForEach-Object { $_.id }) -join "|")
        if ($null -ne $countLabel) { $countLabel.Text = ("{0}{1}" -f $items.Count, $L.Act) }

        if (-not $Force -and $idsKey -eq $script:lastIdsKey -and $items.Count -gt 0) {
            foreach ($it in $items) {
                $id = [string]$it.id
                if ($script:rowLeft.ContainsKey($id)) {
                    $script:rowDue[$id] = [int64]$it.due_unix
                    $script:rowLeft[$id].Text = (Format-Remaining ([int64]$it.due_unix))
                }
            }
            return
        }

        $script:lastIdsKey = $idsKey
        $script:rowLeft = @{}
        $script:rowDue = @{}
        $listHost.Children.Clear()

        if ($items.Count -eq 0) {
            $hint = New-Object System.Windows.Controls.TextBlock
            $hint.Text = $L.EmptyHint
            $hint.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FF94A3B8")
            $hint.FontSize = 13
            $hint.FontFamily = [System.Windows.Media.FontFamily]::new("Segoe UI")
            $hint.HorizontalAlignment = "Center"
            $hint.Margin = [System.Windows.Thickness]::new(8, 24, 8, 0)
            $empty = New-Object System.Windows.Controls.TextBlock
            $empty.Text = $L.EmptyBody
            $empty.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($t.TextMuted)
            $empty.FontSize = 14
            $empty.FontFamily = [System.Windows.Media.FontFamily]::new("Segoe UI")
            $empty.Margin = [System.Windows.Thickness]::new(8, 16, 8, 8)
            $empty.HorizontalAlignment = "Center"
            $empty.TextWrapping = "Wrap"
            [void]$listHost.Children.Add($hint)
            [void]$listHost.Children.Add($empty)
            return
        }
        foreach ($it in $items) {
            [void]$listHost.Children.Add((New-Row $it))
        }
    } catch {
        try {
            $err = Join-Path $env:TEMP "jarvis-timer-list-refresh.err"
            [IO.File]::WriteAllText($err, $_.Exception.ToString(), [Text.UTF8Encoding]::new($false))
        } catch {}
    }
}

Refresh-List -Force

$script:tick = New-Object System.Windows.Threading.DispatcherTimer
$script:tick.Interval = [TimeSpan]::FromSeconds(1)
$script:tick.Add_Tick({ try { Refresh-List } catch {} })
$script:tick.Start()
$window.Add_Closed({ try { $script:tick.Stop() } catch {} })

if ($AutoCloseSec -gt 0) {
    $script:left = $AutoCloseSec
    $script:auto = New-Object System.Windows.Threading.DispatcherTimer
    $script:auto.Interval = [TimeSpan]::FromSeconds(1)
    $script:auto.Add_Tick({
        try {
            $script:left--
            if ($script:left -le 0) { Request-Close }
        } catch { [Environment]::Exit(0) }
    })
    $script:auto.Start()
}

# Do NOT use Set-JarvisHudOverlayStyle here - SWP_NOACTIVATE breaks clicking on some PCs.
try { $window.Activate(); $btnClose.Focus() } catch {}
try {
    [void]$window.ShowDialog()
} catch {}
try { [System.Windows.Application]::Current.Shutdown() } catch {}
[Environment]::Exit(0)
