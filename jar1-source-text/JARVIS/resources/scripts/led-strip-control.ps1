param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet(
        "on", "off", "color", "brightness", "effect", "rgb",
        "speed", "warm", "cold", "colortemp", "temp",
        "mic_on", "mic_off", "mic_eq", "mic_sens",
        "scan", "status", "forget", "ensure"
    )]
    [string]$Action,

    [Parameter(Position = 1)]
    [string]$Value = "",

    [string]$Address = ""
)

# Fast ASCII wrapper. Russian toasts from led-strip-msg.json (UTF-8).
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_jarvis-data-dir.ps1")
. (Join-Path $PSScriptRoot "_jarvis-hidden-process.ps1")

$exeDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = (Resolve-Path (Join-Path $exeDir "..\..")).Path
$pyScript = Join-Path $exeDir "led-strip-ble.py"
$msgJson = Join-Path $exeDir "led-strip-msg.json"
$dataDir = Get-JarvisDataDir
$env:JARVIS_CONFIG_DIR = $dataDir
$pyUser = Join-Path $dataDir "py-led"
$reqMarker = Join-Path $pyUser ".bleak-ok"
$pyCache = Join-Path $pyUser "python-path.txt"

function Resolve-Python {
    if (Test-Path -LiteralPath $pyCache) {
        $cached = (Get-Content -LiteralPath $pyCache -Raw -ErrorAction SilentlyContinue).Trim()
        if ($cached -and (Test-Path -LiteralPath $cached)) { return $cached }
    }
    $candidates = @()
    if ($env:JARVIS_PYTHON) { $candidates += $env:JARVIS_PYTHON }
    $candidates += (Join-Path $root "resources\tts\runtime\python\pythonw.exe")
    $candidates += (Join-Path $root "resources\tts\runtime\python\python.exe")
    $candidates += @(
        "$env:LOCALAPPDATA\Programs\Python\Python313\python.exe",
        "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe",
        "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe",
        "$env:LOCALAPPDATA\Programs\Python\Python310\python.exe"
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c)) {
            New-Item -ItemType Directory -Path $pyUser -Force | Out-Null
            Set-Content -LiteralPath $pyCache -Value $c -Encoding ASCII
            return $c
        }
    }
    return $null
}

function Get-LedMsg([string]$Key, [string]$Arg = "") {
    if (Test-Path -LiteralPath $msgJson) {
        try {
            $map = Get-Content -LiteralPath $msgJson -Raw -Encoding UTF8 | ConvertFrom-Json
            $tpl = [string]$map.$Key
            if ($tpl) {
                if ($Arg -ne "") { return $tpl.Replace("{0}", $Arg) }
                return $tpl
            }
        } catch {}
    }
    return $Key
}

function Show-Toast([string]$title, [string]$message, [string]$kind = "info") {
    $toast = Join-Path $PSScriptRoot "toast.ps1"
    if (-not (Test-Path -LiteralPath $toast)) { return }
    $tmpT = Join-Path $env:TEMP ("jarvis-led-t-" + [guid]::NewGuid().ToString("N") + ".txt")
    $tmpM = Join-Path $env:TEMP ("jarvis-led-m-" + [guid]::NewGuid().ToString("N") + ".txt")
    [IO.File]::WriteAllText($tmpT, $title, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($tmpM, $message, [Text.UTF8Encoding]::new($false))
    Start-JarvisHiddenProcess -FilePath "powershell.exe" -ArgumentList @(
        "-NoProfile", "-STA", "-ExecutionPolicy", "Bypass",
        "-File", $toast, "-Ui", "-TitleFile", $tmpT, "-MessageFile", $tmpM, "-Kind", $kind
    ) | Out-Null
}

function Ensure-Bleak([string]$Py) {
    # Prefer bundled site-packages (ships with JARVIS TTS Python) — no internet on customer PC.
    $probe = (Invoke-JarvisHiddenOutput -FilePath $Py -ArgumentList @("-c", "import bleak; print('ok')")).Output
    if ("$probe" -match "ok") {
        New-Item -ItemType Directory -Path $pyUser -Force | Out-Null
        Set-Content -LiteralPath $reqMarker -Value "1" -Encoding ASCII
        return $true
    }
    $env:PYTHONUSERBASE = $pyUser
    $env:PATH = (Join-Path $pyUser "Scripts") + ";" + $env:PATH
    if (Test-Path -LiteralPath $reqMarker) {
        $probe2 = (Invoke-JarvisHiddenOutput -FilePath $Py -ArgumentList @("-c", "import bleak; print('ok')")).Output
        if ("$probe2" -match "ok") { return $true }
    }
    New-Item -ItemType Directory -Path $pyUser -Force | Out-Null
    Invoke-JarvisHiddenOutput -FilePath $Py -ArgumentList @("-m", "pip", "install", "--user", "--disable-pip-version-check", "-q", "bleak") | Out-Null
    $probe3 = (Invoke-JarvisHiddenOutput -FilePath $Py -ArgumentList @("-c", "import bleak; print('ok')")).Output
    if ("$probe3" -notmatch "ok") {
        Invoke-JarvisHiddenOutput -FilePath $Py -ArgumentList @("-m", "pip", "install", "--disable-pip-version-check", "-q", "bleak") | Out-Null
        $probe3 = (Invoke-JarvisHiddenOutput -FilePath $Py -ArgumentList @("-c", "import bleak; print('ok')")).Output
    }
    if ("$probe3" -notmatch "ok") { return $false }
    Set-Content -LiteralPath $reqMarker -Value "1" -Encoding ASCII
    return $true
}

if (-not (Test-Path -LiteralPath $pyScript)) {
    Show-Toast "LED" (Get-LedMsg "no_script") "error"
    exit 1
}

$py = Resolve-Python
if (-not $py) {
    Show-Toast "LED" (Get-LedMsg "no_python") "error"
    Write-Output "ERR:no_python"
    exit 1
}

if ($Action -eq "ensure") {
    if (Ensure-Bleak $py) { Write-Output "OK:bleak"; exit 0 }
    Show-Toast "LED" (Get-LedMsg "bleak_fail") "error"
    exit 1
}

if (-not (Ensure-Bleak $py)) {
    Show-Toast "LED" (Get-LedMsg "bleak_fail") "error"
    Write-Output "ERR:bleak"
    exit 2
}

$env:PYTHONUSERBASE = $pyUser
$env:PYTHONIOENCODING = "utf-8"
$pyArgs = @($pyScript, $Action)
if ($Value) { $pyArgs += $Value }
if ($Address) { $pyArgs += @("--address", $Address) }
if ($Action -eq "scan") { $pyArgs += @("--save", "--timeout", "4") }

$sw = [Diagnostics.Stopwatch]::StartNew()
$run = Invoke-JarvisHiddenOutput -FilePath $py -ArgumentList $pyArgs
$code = $run.ExitCode
$sw.Stop()
$text = ([string]$run.Output).Trim()
Write-Output $text
Write-Output ("TIME_MS:" + [int]$sw.Elapsed.TotalMilliseconds)

if ($code -ne 0) {
    if ($text -match "no_device") { Show-Toast "LED" (Get-LedMsg "no_device") "error" }
    elseif ($text -match "bleak_missing") { Show-Toast "LED" (Get-LedMsg "bleak_missing") "error" }
    elseif ($text -match "unknown_color") { Show-Toast "LED" (Get-LedMsg "unknown_color") "error" }
    else { Show-Toast "LED" (Get-LedMsg "fail") "error" }
    exit $code
}

switch ($Action) {
    "on" { Show-Toast "LED" (Get-LedMsg "on") "ok" }
    "off" { Show-Toast "LED" (Get-LedMsg "off") "ok" }
    "scan" { Show-Toast "LED" (Get-LedMsg "scan") "ok" }
    "color" { Show-Toast "LED" (Get-LedMsg "color" $Value) "ok" }
    "brightness" { Show-Toast "LED" (Get-LedMsg "brightness" $Value) "ok" }
    "effect" { Show-Toast "LED" (Get-LedMsg "effect" $Value) "ok" }
    "speed" { Show-Toast "LED" (Get-LedMsg "speed" $Value) "ok" }
    "warm" { Show-Toast "LED" (Get-LedMsg "warm") "ok" }
    "cold" { Show-Toast "LED" (Get-LedMsg "cold") "ok" }
    "mic_on" { Show-Toast "LED" (Get-LedMsg "mic_on") "ok" }
    "mic_off" { Show-Toast "LED" (Get-LedMsg "mic_off") "ok" }
}

exit 0
