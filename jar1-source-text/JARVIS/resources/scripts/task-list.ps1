param(
    [int]$AutoCloseSec = 0
)
# JARVIS task list HUD - same chrome as timer-list. ASCII-only source.
$ErrorActionPreference = "Continue"
. (Join-Path $PSScriptRoot "_jarvis-hidden-process.ps1")

try {
    $mutex = [System.Threading.Mutex]::new($false, "Local\JarvisTaskListHud")
    if (-not $mutex.WaitOne(0)) {
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
            $_.ProcessId -ne $PID -and $_.CommandLine -and ($_.CommandLine -match 'task-list\.ps1')
        } | ForEach-Object {
            try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch {}
        }
        Start-Sleep -Milliseconds 250
        if (-not $mutex.WaitOne(0)) { exit 0 }
    }
} catch {}

. (Join-Path $PSScriptRoot "_jarvis-data-dir.ps1")
$StorePath = (Join-Path (Get-JarvisDataDir) "tasks.json")
$MaxTasks = 30

. (Join-Path $PSScriptRoot "jarvis-hud-theme.ps1")
Ensure-JarvisHudAssemblies
$t = Get-JarvisHudTheme
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
    Title       = U8 @(0x4A,0x41,0x52,0x56,0x49,0x53,0x20,0xE2,0x80,0x94,0x20,0xD0,0x97,0xD0,0xB0,0xD0,0xB4,0xD0,0xB0,0xD1,0x87,0xD0,0xB8)
    PageTitle   = U8 @(0xD0,0x97,0xD0,0xB0,0xD0,0xB4,0xD0,0xB0,0xD1,0x87,0xD0,0xB8)
    Add         = U8 @(0xD0,0x94,0xD0,0xBE,0xD0,0xB1,0xD0,0xB0,0xD0,0xB2,0xD0,0xB8,0xD1,0x82,0xD1,0x8C)
    Delete      = U8 @(0xD0,0xA3,0xD0,0x94,0xD0,0x90,0xD0,0x9B)
    Edit        = U8 @(0xD0,0x98,0xD0,0x97,0xD0,0x9C)
    Save        = U8 @(0xD0,0xA1,0xD0,0x9E,0xD0,0xA5,0xD0,0xA0,0xD0,0x90,0xD0,0x9D,0xD0,0x98,0xD0,0xA2,0xD0,0xAC)
    Back        = U8 @(0xD0,0x9D,0xD0,0x90,0xD0,0x97,0xD0,0x90,0xD0,0x94)
    Clear       = U8 @(0xD0,0xA1,0xD1,0x82,0xD0,0xB5,0xD1,0x80,0xD0,0xB5,0xD1,0x82,0xD1,0x8C,0x20,0xD0,0xB2,0xD1,0x81,0xD0,0xB5)
    ClearSure   = U8 @(0xD0,0xA2,0xD0,0xBE,0xD1,0x87,0xD0,0xBD,0xD0,0xBE,0x20,0xD1,0x81,0xD1,0x82,0xD0,0xB5,0xD1,0x80,0xD0,0xB5,0xD1,0x82,0xD1,0x8C)
    Cancel      = U8 @(0xD0,0x9E,0xD1,0x82,0xD0,0xBC,0xD0,0xB5,0xD0,0xBD,0xD0,0xB0)
    Close       = U8 @(0xD0,0x97,0xD0,0xB0,0xD0,0xBA,0xD1,0x80,0xD1,0x8B,0xD1,0x82,0xD1,0x8C)
    EmptyBody   = U8 @(0xD0,0x9D,0xD0,0xB5,0xD1,0x82,0x20,0xD0,0xB7,0xD0,0xB0,0xD0,0xB4,0xD0,0xB0,0xD1,0x87)
    EmptyHint   = "JARVIS  //  " + (U8 @(0xD0,0x97,0xD0,0x90,0xD0,0x94,0xD0,0x90,0xD0,0xA7,0xD0,0x98))
    ToastTitle  = U8 @(0xD0,0x97,0xD0,0xB0,0xD0,0xB4,0xD0,0xB0,0xD1,0x87,0xD0,0xB8)
    ToastCleared= U8 @(0xD0,0xA1,0xD0,0xBF,0xD0,0xB8,0xD1,0x81,0xD0,0xBE,0xD0,0xBA,0x20,0xD0,0xBE,0xD1,0x87,0xD0,0xB8,0xD1,0x89,0xD0,0xB5,0xD0,0xBD)
    ToastAdded  = U8 @(0xD0,0x97,0xD0,0xB0,0xD0,0xB4,0xD0,0xB0,0xD1,0x87,0xD0,0xB0,0x20,0xD0,0xB4,0xD0,0xBE,0xD0,0xB1,0xD0,0xB0,0xD0,0xB2,0xD0,0xBB,0xD0,0xB5,0xD0,0xBD,0xD0,0xB0)
    ToastSaved  = U8 @(0xD0,0xA1,0xD0,0xBE,0xD1,0x85,0xD1,0x80,0xD0,0xB0,0xD0,0xBD,0xD0,0xB5,0xD0,0xBD,0xD0,0xBE)
    ToastFull   = U8 @(0xD0,0xA3,0xD0,0xB6,0xD0,0xB5,0x20,0x33,0x30,0x20,0xD0,0xB7,0xD0,0xB0,0xD0,0xB4,0xD0,0xB0,0xD1,0x87)
    ToastEmpty  = U8 @(0xD0,0x92,0xD0,0xB2,0xD0,0xB5,0xD0,0xB4,0xD0,0xB8,0x20,0xD1,0x82,0xD0,0xB5,0xD0,0xBA,0xD1,0x81,0xD1,0x82)
    ToastFail   = U8 @(0xD0,0x9D,0xD0,0xB5,0x20,0xD1,0x83,0xD0,0xB4,0xD0,0xB0,0xD0,0xBB,0xD0,0xBE,0xD1,0x81,0xD1,0x8C,0x20,0xD1,0x81,0xD0,0xBE,0xD1,0x85,0xD1,0x80,0xD0,0xB0,0xD0,0xBD,0xD0,0xB8,0xD1,0x82,0xD1,0x8C)
    AddHint     = U8 @(0xD0,0x9D,0xD0,0xBE,0xD0,0xB2,0xD0,0xB0,0xD1,0x8F,0x20,0xD0,0xB7,0xD0,0xB0,0xD0,0xB4,0xD0,0xB0,0xD1,0x87,0xD0,0xB0)
    EditTitle   = U8 @(0xD0,0x98,0xD0,0xB7,0xD0,0xBC,0xD0,0xB5,0xD0,0xBD,0xD0,0xB8,0xD1,0x82,0xD1,0x8C,0x20,0xD0,0xB7,0xD0,0xB0,0xD0,0xB4,0xD0,0xB0,0xD1,0x87,0xD1,0x83)
}

function Read-TaskStore {
    if (-not (Test-Path -LiteralPath $StorePath)) { return @() }
    try {
        $raw = [IO.File]::ReadAllBytes($StorePath)
        if ($raw.Length -ge 3 -and $raw[0] -eq 0xEF -and $raw[1] -eq 0xBB -and $raw[2] -eq 0xBF) {
            $raw = $raw[3..($raw.Length - 1)]
        }
        $obj = ([Text.Encoding]::UTF8.GetString($raw)) | ConvertFrom-Json
        if ($null -eq $obj.items) { return @() }
        $items = @($obj.items)
        $out = @()
        foreach ($it in $items) {
            $text = Clamp-TaskText ([string]$it.text)
            if ([string]::IsNullOrWhiteSpace($text)) { continue }
            $created = 0
            try { $created = [int64]$it.created_unix } catch { $created = 0 }
            $out += [pscustomobject]@{
                id           = [string]$it.id
                text         = $text
                created_unix = $created
            }
        }
        return @($out)
    } catch { return @() }
}

function New-TaskId {
    -join ((1..12) | ForEach-Object { '{0:x}' -f (Get-Random -Maximum 16) })
}
function Get-JarvisUnixNow {
    return [int64]([DateTime]::UtcNow - [datetime]'1970-01-01').TotalSeconds
}
function Clamp-TaskText([string]$text) {
    $t = ([string]$text).Trim()
    $hint = [string]$L.AddHint
    if (-not [string]::IsNullOrWhiteSpace($hint)) {
        if ($t -eq $hint) { return "" }
        if ($t.EndsWith($hint)) { $t = $t.Substring(0, $t.Length - $hint.Length).TrimEnd() }
        elseif ($t.StartsWith($hint)) { $t = $t.Substring($hint.Length).TrimStart() }
    }
    if ([string]::IsNullOrWhiteSpace($t)) { return "" }
    $chars = @($t.ToCharArray())
    if ($chars.Count -le 200) { return $t }
    return (-join $chars[0..199])
}
function Escape-JarvisJson([string]$s) {
    if ($null -eq $s) { return "" }
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $s.ToCharArray()) {
        $code = [int][char]$ch
        if ($ch -eq '"') { [void]$sb.Append('\"'); continue }
        if ($ch -eq '\') { [void]$sb.Append('\\'); continue }
        if ($code -lt 32) { [void]$sb.Append(('\u{0:x4}' -f $code)); continue }
        [void]$sb.Append($ch)
    }
    return $sb.ToString()
}
function Save-TaskItems($items) {
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($it in @($items)) {
        $text = Clamp-TaskText ([string]$it.text)
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        $id = Escape-JarvisJson ([string]$it.id)
        $esc = Escape-JarvisJson $text
        $created = 0
        try { $created = [int64]$it.created_unix } catch { $created = 0 }
        if ($created -le 0) { $created = Get-JarvisUnixNow }
        [void]$parts.Add(('{"id":"' + $id + '","text":"' + $esc + '","created_unix":' + $created + '}'))
    }
    $json = '{"items":[' + ($parts -join ',') + ']}'
    $dir = Split-Path -Parent $StorePath
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $tmp = Join-Path $dir ("tasks-" + [guid]::NewGuid().ToString("N") + ".tmp")
    [IO.File]::WriteAllText($tmp, $json, [Text.UTF8Encoding]::new($false))
    try {
        Move-Item -LiteralPath $tmp -Destination $StorePath -Force
    } catch {
        try { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue } catch {}
        throw
    }
}

function Add-Task([string]$text) {
    $t = Clamp-TaskText $text
    if ([string]::IsNullOrWhiteSpace($t)) { return "empty" }
    $items = @(Read-TaskStore)
    if ($items.Count -ge $MaxTasks) { return "full" }
    $items += [pscustomobject]@{
        id           = (New-TaskId)
        text         = $t
        created_unix = (Get-JarvisUnixNow)
    }
    try { Save-TaskItems $items; return "ok" } catch { return "err" }
}

function Set-Task([string]$id, [string]$text) {
    $t = Clamp-TaskText $text
    if ([string]::IsNullOrWhiteSpace($id) -or [string]::IsNullOrWhiteSpace($t)) { return $false }
    $items = @()
    $found = $false
    foreach ($it in @(Read-TaskStore)) {
        if ([string]$it.id -eq $id) {
            $it.text = $t
            $found = $true
        }
        $items += $it
    }
    if (-not $found) { return $false }
    try { Save-TaskItems $items; return $true } catch { return $false }
}

function Remove-Task([string]$id) {
    if ([string]::IsNullOrWhiteSpace($id)) { return }
    $items = @(@(Read-TaskStore) | Where-Object { [string]$_.id -ne $id })
    try { Save-TaskItems $items } catch {}
}

function Clear-Tasks {
    try { Save-TaskItems @() } catch {}
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
$safeAdd = Escape-JarvisHudText $L.Add
$safeClear = Escape-JarvisHudText $L.Clear
$safeClose = Escape-JarvisHudText $L.Close
$safeEditTitle = Escape-JarvisHudText $L.EditTitle
$safeSave = Escape-JarvisHudText $L.Save
$safeBack = Escape-JarvisHudText $L.Back
$safeAddHint = Escape-JarvisHudText $L.AddHint

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
        Width="560" Height="640"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        ShowInTaskbar="True" Topmost="True" ResizeMode="NoResize" Opacity="1"
        ShowActivated="True" WindowStartupLocation="CenterScreen">
  <Window.Resources>
$appearScaleOnly
    <Style x:Key="HudScrollThumb" TargetType="Thumb">
      <Setter Property="OverridesDefaultStyle" Value="True"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Thumb">
            <Border Background="#55FFFFFF" CornerRadius="5" Margin="1,2"/>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="HudScrollBar" TargetType="ScrollBar">
      <Setter Property="Stylus.IsPressAndHoldEnabled" Value="False"/>
      <Setter Property="Stylus.IsFlicksEnabled" Value="False"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Width" Value="10"/>
      <Setter Property="MinWidth" Value="10"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ScrollBar">
            <Grid SnapsToDevicePixels="True" Margin="0,8,4,8">
              <Border Background="#18FFFFFF" CornerRadius="5"/>
              <Track x:Name="PART_Track" IsDirectionReversed="True" Focusable="False">
                <Track.DecreaseRepeatButton>
                  <RepeatButton Command="ScrollBar.PageUpCommand" IsTabStop="False" Focusable="False">
                    <RepeatButton.Template>
                      <ControlTemplate TargetType="RepeatButton"><Border Background="Transparent"/></ControlTemplate>
                    </RepeatButton.Template>
                  </RepeatButton>
                </Track.DecreaseRepeatButton>
                <Track.Thumb>
                  <Thumb Style="{StaticResource HudScrollThumb}"/>
                </Track.Thumb>
                <Track.IncreaseRepeatButton>
                  <RepeatButton Command="ScrollBar.PageDownCommand" IsTabStop="False" Focusable="False">
                    <RepeatButton.Template>
                      <ControlTemplate TargetType="RepeatButton"><Border Background="Transparent"/></ControlTemplate>
                    </RepeatButton.Template>
                  </RepeatButton>
                </Track.IncreaseRepeatButton>
              </Track>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="HudListScroll" TargetType="ScrollViewer">
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ScrollViewer">
            <Grid>
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
              </Grid.ColumnDefinitions>
              <ScrollContentPresenter Grid.Column="0"
                                      CanContentScroll="{TemplateBinding CanContentScroll}"
                                      Content="{TemplateBinding Content}"
                                      ContentTemplate="{TemplateBinding ContentTemplate}"
                                      Margin="{TemplateBinding Padding}"/>
              <ScrollBar x:Name="PART_VerticalScrollBar" Grid.Column="1"
                         Style="{StaticResource HudScrollBar}"
                         Orientation="Vertical"
                         ViewportSize="{TemplateBinding ViewportHeight}"
                         Maximum="{TemplateBinding ScrollableHeight}"
                         Value="{Binding VerticalOffset, Mode=OneWay, RelativeSource={RelativeSource TemplatedParent}}"
                         Visibility="{TemplateBinding ComputedVerticalScrollBarVisibility}"/>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <Grid Margin="28">
    <Grid.RenderTransform>
      <TransformGroup>
        <ScaleTransform x:Name="RootScale" ScaleX="1" ScaleY="1" CenterX="252" CenterY="292"/>
        <TranslateTransform x:Name="RootTranslate" Y="0"/>
      </TransformGroup>
    </Grid.RenderTransform>

    <Border CornerRadius="26" Background="#E610141C">
      <Border.Effect>
        <DropShadowEffect Color="#000000" BlurRadius="64" ShadowDepth="6" Direction="270" Opacity="0.38"/>
      </Border.Effect>
    </Border>

    <Border x:Name="ShimmerA" CornerRadius="26" IsHitTestVisible="False" Opacity="0.32">
      <Border.Background>
        <RadialGradientBrush x:Name="GlowA" Center="0.12,0.92" GradientOrigin="0.12,0.92" RadiusX="1.15" RadiusY="0.90">
          <GradientStop x:Name="GlowAStop0" Color="#335B4DFF" Offset="0"/>
          <GradientStop Color="#182A5A8A" Offset="0.55"/>
          <GradientStop Color="#00000000" Offset="1"/>
        </RadialGradientBrush>
      </Border.Background>
    </Border>
    <Border x:Name="ShimmerB" CornerRadius="26" IsHitTestVisible="False" Opacity="0.20">
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
          <ScrollViewer x:Name="ListScroll" Style="{StaticResource HudListScroll}"
                        VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled"
                        Padding="16,10,8,14">
            <StackPanel x:Name="ListHost"/>
          </ScrollViewer>

          <Border x:Name="EditPanel" Visibility="Collapsed" Background="Transparent" Padding="16,8,16,8">
            <Grid>
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
                  </Grid.RowDefinitions>
                  <TextBlock Grid.Row="0" Text="$safeEditTitle" FontFamily="Segoe UI" FontSize="16" FontWeight="Bold" Foreground="#FFFFFFFF"/>
                  <Border Grid.Row="1" Height="40" Margin="0,14,0,0" CornerRadius="10"
                          Background="#FF0D1118" BorderBrush="#33FFFFFF" BorderThickness="1">
                    <Grid>
                      <TextBox x:Name="EditBox" Height="38" Padding="12,8"
                               FontFamily="Segoe UI" FontSize="14"
                               Background="Transparent" BorderThickness="0"
                               Foreground="Transparent" CaretBrush="#FFF2F5F8"
                               VerticalContentAlignment="Center" MaxLength="200"
                               HorizontalScrollBarVisibility="Hidden" VerticalScrollBarVisibility="Disabled"/>
                      <TextBlock x:Name="EditInk" IsHitTestVisible="False"
                                 FontFamily="Segoe UI" FontSize="14" Foreground="#FFF2F5F8"
                                 VerticalAlignment="Center" Margin="14,0,14,0"
                                 TextTrimming="CharacterEllipsis"/>
                    </Grid>
                  </Border>
                  <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,16,0,0">
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
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
            <Grid Grid.Row="0" Margin="0,0,0,10">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
              </Grid.ColumnDefinitions>
              <Border Grid.Column="0" Height="36" Margin="0,0,8,0" CornerRadius="10"
                      Background="#FF0D1118" BorderBrush="#33FFFFFF" BorderThickness="1">
                <Grid>
                  <TextBox x:Name="AddBox" Height="34" Padding="12,7"
                           FontFamily="Segoe UI" FontSize="14"
                           Background="Transparent" BorderThickness="0"
                           Foreground="Transparent" CaretBrush="#FFF2F5F8"
                           VerticalContentAlignment="Center" MaxLength="200"
                           HorizontalScrollBarVisibility="Hidden" VerticalScrollBarVisibility="Disabled"/>
                  <TextBlock x:Name="AddInk" IsHitTestVisible="False"
                             FontFamily="Segoe UI" FontSize="14" Foreground="#FFF2F5F8"
                             VerticalAlignment="Center" Margin="14,0,14,0"
                             TextTrimming="CharacterEllipsis"/>
                  <TextBlock x:Name="AddHint" Text="$safeAddHint" IsHitTestVisible="False"
                             FontFamily="Segoe UI" FontSize="14" Foreground="#FF94A3B8"
                             VerticalAlignment="Center" Margin="14,0,14,0"/>
                </Grid>
              </Border>
              <Button x:Name="BtnAdd" Grid.Column="1" Content="$safeAdd" MinWidth="110" Height="36" Padding="14,0"
                      FontFamily="Segoe UI" FontSize="13" FontWeight="SemiBold"
                      Foreground="$btnOn" Background="$btnMatte" BorderThickness="0"
                      Cursor="Hand" Template="{StaticResource Btn3dPrimary}"/>
            </Grid>
            <Grid Grid.Row="1">
              <Button x:Name="BtnClear" Content="$safeClear" HorizontalAlignment="Left" MinWidth="156" Height="36" Padding="16,0"
                      FontFamily="Segoe UI" FontSize="13" FontWeight="SemiBold"
                      Foreground="$btnOn" Background="$btnGhost" BorderThickness="0"
                      Cursor="Hand" Focusable="False" Template="{StaticResource Btn3dGhost}"/>
              <Button x:Name="BtnClose" Content="$safeClose" HorizontalAlignment="Right" MinWidth="120" Height="36" Padding="16,0"
                      FontFamily="Segoe UI" FontSize="13" FontWeight="SemiBold"
                      Foreground="$btnOn" Background="$btnMatte" BorderThickness="0"
                      Cursor="Hand" Template="{StaticResource Btn3dPrimary}"/>
            </Grid>
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
        [IO.File]::WriteAllText((Join-Path $env:TEMP "jarvis-task-list-boot.err"), $_.Exception.ToString(), [Text.UTF8Encoding]::new($false))
    } catch {}
    [Environment]::Exit(1)
}

$header = $window.FindName("Header")
$listHost = $window.FindName("ListHost")
$countLabel = $window.FindName("CountLabel")
$btnClose = $window.FindName("BtnClose")
$btnX = $window.FindName("BtnX")
$btnClear = $window.FindName("BtnClear")
$btnAdd = $window.FindName("BtnAdd")
$addBox = $window.FindName("AddBox")
$addInk = $window.FindName("AddInk")
$addHint = $window.FindName("AddHint")
$editPanel = $window.FindName("EditPanel")
$listScroll = $window.FindName("ListScroll")
$editBox = $window.FindName("EditBox")
$editInk = $window.FindName("EditInk")
$btnEditBack = $window.FindName("BtnEditBack")
$btnEditSave = $window.FindName("BtnEditSave")
Set-JarvisHudMatteButton -Button $btnClose -Kind primary -Template $tplPrimary
Set-JarvisHudMatteButton -Button $btnClear -Kind secondary -Template $tplSecondary
Set-JarvisHudMatteButton -Button $btnAdd -Kind primary -Template $tplPrimary
Set-JarvisHudMatteButton -Button $btnEditBack -Kind secondary -Template $tplSecondary
Set-JarvisHudMatteButton -Button $btnEditSave -Kind primary -Template $tplPrimary
Set-JarvisHudMatteButton -Button $btnX -Kind secondary -Template $tplX
Set-JarvisHudLayeredWindow $window
Set-JarvisHudInputInk -Box $addBox -Ink $addInk -Hint $addHint
Set-JarvisHudInputInk -Box $editBox -Ink $editInk

$script:closeRequested = $false
$script:editId = $null
$script:lastIdsKey = ""
$script:editing = $false
$script:confirmClear = $false

function Repair-StoredHints {
    try {
        if (-not (Test-Path -LiteralPath $StorePath)) { return }
        $raw = [IO.File]::ReadAllText($StorePath, [Text.UTF8Encoding]::new($false))
        if ($raw.IndexOf($L.AddHint) -lt 0) { return }
        Save-TaskItems @(Read-TaskStore)
    } catch {}
}

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

function Reset-ClearConfirm {
    $script:confirmClear = $false
    try { $btnClear.Content = $L.Clear } catch {}
}

function Hide-Edit {
    $script:editing = $false
    $script:editId = $null
    $editPanel.Visibility = "Collapsed"
    $listScroll.Visibility = "Visible"
    $btnClear.IsEnabled = $true
    $btnAdd.IsEnabled = $true
}

function Show-Edit([string]$id, [string]$text) {
    Reset-ClearConfirm
    $script:editing = $true
    $script:editId = $id
    $editBox.Text = $text
    $listScroll.Visibility = "Collapsed"
    $editPanel.Visibility = "Visible"
    $btnClear.IsEnabled = $false
    $btnAdd.IsEnabled = $false
    try { $editBox.Focus(); $editBox.CaretIndex = $editBox.Text.Length } catch {}
}

function Apply-Edit {
    if ([string]::IsNullOrWhiteSpace($script:editId)) { return }
    $t = ([string]$editBox.Text).Trim()
    if ([string]::IsNullOrWhiteSpace($t)) {
        Show-JarvisToast $L.ToastTitle $L.ToastEmpty "error"
        return
    }
    if (Set-Task $script:editId $t) {
        Hide-Edit
        Refresh-List -Force
        Show-JarvisToast $L.ToastTitle $L.ToastSaved "ok"
    } else {
        Show-JarvisToast $L.ToastTitle $L.ToastFail "error"
    }
}

function Submit-Add {
    Reset-ClearConfirm
    $t = Clamp-TaskText $addBox.Text
    if ([string]::IsNullOrWhiteSpace($t)) {
        Show-JarvisToast $L.ToastTitle $L.ToastEmpty "error"
        return
    }
    $st = Add-Task $t
    if ($st -eq "ok") {
        $addBox.Text = ""
        Refresh-List -Force
        Show-JarvisToast $L.ToastTitle $L.ToastAdded "ok"
        try { $addBox.Focus() } catch {}
    } elseif ($st -eq "full") {
        Show-JarvisToast $L.ToastTitle $L.ToastFull "error"
    } elseif ($st -eq "empty") {
        Show-JarvisToast $L.ToastTitle $L.ToastEmpty "error"
    } else {
        Show-JarvisToast $L.ToastTitle $L.ToastFail "error"
    }
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
            if ($script:editing) { Hide-Edit } elseif ($script:confirmClear) { Reset-ClearConfirm } else { Request-Close }
        }
        elseif ($e.Key -eq "Return") {
            if ($script:editing) { Apply-Edit }
            elseif ($addBox.IsKeyboardFocusWithin) { Submit-Add }
        }
    } catch { [Environment]::Exit(0) }
})
$btnEditBack.Add_Click({ Hide-Edit })
$btnEditSave.Add_Click({ Apply-Edit })
$btnAdd.Add_Click({ Submit-Add })
$btnClear.Add_Click({
    try {
        if (-not $script:confirmClear) {
            $script:confirmClear = $true
            $btnClear.Content = $L.ClearSure
            return
        }
        Clear-Tasks
        Reset-ClearConfirm
        Hide-Edit
        Refresh-List -Force
        Show-JarvisToast $L.ToastTitle $L.ToastCleared "ok"
    } catch {}
})

$appear = $window.Resources["Appear"]
$window.Add_ContentRendered({
    try { $appear.Begin($window) } catch {}
})

$script:fontUi = [System.Windows.Media.FontFamily]::new("Segoe UI")
$script:brushMuted = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(0x94, 0xA3, 0xB8))
$script:brushMuted.Freeze()
$script:brushInk = Get-JarvisHudInkBrush
$script:brushInk.Freeze()
$script:brushShade = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(0x3A, 0, 0, 0))
$script:brushShade.Freeze()
$script:cardBg = New-Object System.Windows.Media.LinearGradientBrush
$script:cardBg.StartPoint = [System.Windows.Point]::new(0, 0)
$script:cardBg.EndPoint = [System.Windows.Point]::new(0, 1)
$gs0 = New-Object System.Windows.Media.GradientStop
$gs0.Color = [System.Windows.Media.Color]::FromArgb(0xEE, 0x1C, 0x25, 0x32); $gs0.Offset = 0
$gs1 = New-Object System.Windows.Media.GradientStop
$gs1.Color = [System.Windows.Media.Color]::FromArgb(0xEE, 0x12, 0x18, 0x22); $gs1.Offset = 1
[void]$script:cardBg.GradientStops.Add($gs0)
[void]$script:cardBg.GradientStops.Add($gs1)
$script:cardBg.Freeze()
$script:cardEdge = New-Object System.Windows.Media.LinearGradientBrush
$script:cardEdge.StartPoint = [System.Windows.Point]::new(0, 0)
$script:cardEdge.EndPoint = [System.Windows.Point]::new(0, 1)
$ge0 = New-Object System.Windows.Media.GradientStop
$ge0.Color = [System.Windows.Media.Color]::FromArgb(0x38, 0xFF, 0xFF, 0xFF); $ge0.Offset = 0
$ge1 = New-Object System.Windows.Media.GradientStop
$ge1.Color = [System.Windows.Media.Color]::FromArgb(0x12, 0xFF, 0xFF, 0xFF); $ge1.Offset = 1
[void]$script:cardEdge.GradientStops.Add($ge0)
[void]$script:cardEdge.GradientStops.Add($ge1)
$script:cardEdge.Freeze()

function New-Row($item, [int]$num) {
    $id = [string]$item.id
    $label = [string]$item.text

    $wrap = New-Object System.Windows.Controls.Grid
    $wrap.Margin = [System.Windows.Thickness]::new(0, 0, 0, 14)

    $shade = New-Object System.Windows.Controls.Border
    $shade.CornerRadius = [System.Windows.CornerRadius]::new(18)
    $shade.Background = $script:brushShade
    $shade.Margin = [System.Windows.Thickness]::new(2, 8, 2, -3)
    $shade.IsHitTestVisible = $false

    $row = New-Object System.Windows.Controls.Border
    $row.Padding = [System.Windows.Thickness]::new(16, 14, 16, 14)
    $row.CornerRadius = [System.Windows.CornerRadius]::new(16)
    $row.BorderThickness = [System.Windows.Thickness]::new(1)
    $row.Tag = $id
    $row.Background = $script:cardBg
    $row.BorderBrush = $script:cardEdge

    $g = New-Object System.Windows.Controls.Grid
    $cNum = New-Object System.Windows.Controls.ColumnDefinition; $cNum.Width = [System.Windows.GridLength]::new(36)
    $c0 = New-Object System.Windows.Controls.ColumnDefinition; $c0.Width = [System.Windows.GridLength]::new(1, "Star")
    $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = [System.Windows.GridLength]::Auto
    [void]$g.ColumnDefinitions.Add($cNum)
    [void]$g.ColumnDefinitions.Add($c0)
    [void]$g.ColumnDefinitions.Add($c1)

    $tbNum = New-Object System.Windows.Controls.TextBlock
    $tbNum.Text = ("{0}." -f $num)
    $tbNum.FontFamily = $script:fontUi
    $tbNum.FontSize = 16
    $tbNum.FontWeight = "Bold"
    $tbNum.Foreground = $script:brushMuted
    $tbNum.VerticalAlignment = "Center"
    [System.Windows.Controls.Grid]::SetColumn($tbNum, 0)
    [void]$g.Children.Add($tbNum)

    $tbLabel = New-Object System.Windows.Controls.TextBlock
    $tbLabel.Text = $label
    $tbLabel.FontFamily = $script:fontUi
    $tbLabel.FontSize = 15
    $tbLabel.FontWeight = "SemiBold"
    $tbLabel.Foreground = $script:brushInk
    $tbLabel.TextWrapping = "Wrap"
    $tbLabel.VerticalAlignment = "Center"
    $tbLabel.Margin = [System.Windows.Thickness]::new(0, 0, 8, 0)
    [System.Windows.Controls.Grid]::SetColumn($tbLabel, 1)
    [void]$g.Children.Add($tbLabel)

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
    $btnE.Tag = @{ Id = $id; Text = $label }
    $btnE.Add_Click({
        param($s, $e)
        $tag = $s.Tag
        Show-Edit ([string]$tag.Id) ([string]$tag.Text)
    })

    $btnD = New-Object System.Windows.Controls.Button
    $btnD.Content = $L.Delete
    $btnD.Width = 72; $btnD.Height = 28
    $btnD.FontSize = 12
    Set-JarvisHudMatteButton -Button $btnD -Kind secondary -Template $tplSecondary
    $btnD.Tag = $id
    $btnD.Add_Click({
        param($s, $e)
        Reset-ClearConfirm
        Remove-Task ([string]$s.Tag)
        Refresh-List -Force
    })

    [void]$btns.Children.Add($btnE)
    [void]$btns.Children.Add($btnD)
    [System.Windows.Controls.Grid]::SetColumn($btns, 2)
    [void]$g.Children.Add($btns)
    $row.Child = $g
    [void]$wrap.Children.Add($shade)
    [void]$wrap.Children.Add($row)
    return $wrap
}

function Refresh-List {
    param([switch]$Force)
    if ($script:editing -and -not $Force) { return }
    try {
        $items = @(Read-TaskStore)
        $idsKey = (($items | ForEach-Object { $_.id + "=" + $_.text }) -join "|")
        if ($null -ne $countLabel) { $countLabel.Text = ("{0} / {1}" -f $items.Count, $MaxTasks) }
        $full = $items.Count -ge $MaxTasks
        $btnAdd.IsEnabled = -not $full -and -not $script:editing
        $addBox.IsEnabled = -not $full -and -not $script:editing

        if (-not $Force -and $idsKey -eq $script:lastIdsKey) { return }
        $script:lastIdsKey = $idsKey
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
        $n = 1
        foreach ($it in $items) {
            [void]$listHost.Children.Add((New-Row $it $n))
            $n++
        }
    } catch {
        try {
            $err = Join-Path $env:TEMP "jarvis-task-list-refresh.err"
            [IO.File]::WriteAllText($err, $_.Exception.ToString(), [Text.UTF8Encoding]::new($false))
        } catch {}
    }
}

Repair-StoredHints
$addBox.Text = ""
Refresh-List -Force

$script:tick = New-Object System.Windows.Threading.DispatcherTimer
$script:tick.Interval = [TimeSpan]::FromSeconds(4)
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

try { $window.Activate(); $addBox.Focus() } catch {}
try {
    [void]$window.ShowDialog()
} catch {}
try { [System.Windows.Application]::Current.Shutdown() } catch {}
[Environment]::Exit(0)
