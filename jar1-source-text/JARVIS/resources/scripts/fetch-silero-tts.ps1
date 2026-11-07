# Download / repair Silero TTS: prefer v5_5_ru.pt, fallback v5_ru.pt.
# Always installs the heavy runtime to %ProgramData%\JARVIS\tts (any PC:
# Program Files, Cyrillic user path, OneDrive portable folder).
# CPU torch only. ASCII-only for PS 5.1. Safe to re-run.
$ErrorActionPreference = "Stop"

function Resolve-JarvisRoot {
  $probe = $PSScriptRoot
  for ($i = 0; $i -lt 6; $i++) {
    $res = Join-Path $probe "resources"
    if (Test-Path -LiteralPath $res) { return $probe }
    $parent = Split-Path -Parent $probe
    if (-not $parent -or $parent -eq $probe) { break }
    $probe = $parent
  }
  throw "Cannot locate JARVIS root from $PSScriptRoot"
}

$Root = Resolve-JarvisRoot
$helper = Join-Path $Root "resources\scripts\_download-file.ps1"
if (-not (Test-Path -LiteralPath $helper)) {
  $helper = Join-Path $PSScriptRoot "_download-file.ps1"
}
if (-not (Test-Path -LiteralPath $helper)) { throw "Missing _download-file.ps1" }
. $helper
$pyEnv = Join-Path $Root "resources\scripts\_jarvis-python-env.ps1"
if (-not (Test-Path -LiteralPath $pyEnv)) { $pyEnv = Join-Path $PSScriptRoot "_jarvis-python-env.ps1" }
if (Test-Path -LiteralPath $pyEnv) { . $pyEnv }
if (Get-Command Clear-JarvisPythonEnv -ErrorAction SilentlyContinue) {
  Clear-JarvisPythonEnv
}

if (-not [Environment]::Is64BitOperatingSystem) {
  throw "Silero needs 64-bit Windows."
}

$programData = $env:ProgramData
if ([string]::IsNullOrWhiteSpace($programData)) { $programData = "C:\ProgramData" }
$Tts = Join-Path $programData "JARVIS\tts"

$Runtime = Join-Path $Tts "runtime"
$Models = Join-Path $Tts "models"
$PyDir = Join-Path $Runtime "python"
$PyExe = Join-Path $PyDir "python.exe"
$ModelPreferred = Join-Path $Models "v5_5_ru.pt"
$ModelFallback = Join-Path $Models "v5_ru.pt"
$Marker = Join-Path $Runtime ".ready"

$PyZipUrls = @(
  "https://www.python.org/ftp/python/3.11.9/python-3.11.9-embed-amd64.zip",
  "https://npmmirror.com/mirrors/python/3.11.9/python-3.11.9-embed-amd64.zip",
  "https://registry.npmmirror.com/-/binary/python/3.11.9/python-3.11.9-embed-amd64.zip"
)
$GetPipUrls = @(
  "https://bootstrap.pypa.io/get-pip.py",
  "https://cdn.jsdelivr.net/gh/pypa/get-pip@main/public/get-pip.py",
  "https://npmmirror.com/mirrors/get-pip/get-pip.py"
)
$UrlV55List = @(
  "https://models.silero.ai/models/tts/ru/v5_5_ru.pt",
  "https://ghfast.top/https://models.silero.ai/models/tts/ru/v5_5_ru.pt",
  "https://mirror.ghproxy.com/https://models.silero.ai/models/tts/ru/v5_5_ru.pt"
)
$UrlV5List = @(
  "https://models.silero.ai/models/tts/ru/v5_ru.pt",
  "https://ghfast.top/https://models.silero.ai/models/tts/ru/v5_ru.pt",
  "https://mirror.ghproxy.com/https://models.silero.ai/models/tts/ru/v5_ru.pt"
)

New-Item -ItemType Directory -Force -Path $Tts, $Runtime, $Models, $PyDir | Out-Null

$bundledSpeak = Join-Path $Root "resources\tts\speak.py"
$bundledDaemon = Join-Path $Root "resources\tts\tts_daemon.py"
$speak = Join-Path $Tts "speak.py"
if (Test-Path -LiteralPath $bundledSpeak) {
  Copy-Item -LiteralPath $bundledSpeak -Destination $speak -Force
}
if (Test-Path -LiteralPath $bundledDaemon) {
  Copy-Item -LiteralPath $bundledDaemon -Destination (Join-Path $Tts "tts_daemon.py") -Force
}
if (-not (Test-Path -LiteralPath $speak)) {
  throw "Missing bundled speak.py at $bundledSpeak"
}

function Test-NotReparse([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { return $true }
  $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
  if (-not $item) { return $false }
  return -not [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
}

function Test-SileroFiles([string]$Root) {
  if ([string]::IsNullOrWhiteSpace($Root)) { return $false }
  if (-not (Test-NotReparse $Root)) { return $false }
  if (-not (Test-NotReparse (Join-Path $Root "runtime"))) { return $false }
  $py = Join-Path $Root "runtime\python\python.exe"
  $sp = Join-Path $Root "speak.py"
  $pyDir = Join-Path $Root "runtime\python"
  $m55 = Join-Path $Root "models\v5_5_ru.pt"
  $m5 = Join-Path $Root "models\v5_ru.pt"
  if (-not (Test-Path -LiteralPath $py)) { return $false }
  if (-not (Test-Path -LiteralPath $sp)) { return $false }
  $torchOk = $false
  if (Get-Command Test-JarvisTorchTree -ErrorAction SilentlyContinue) {
    $torchOk = Test-JarvisTorchTree $pyDir
  } else {
    $init = Join-Path $pyDir "Lib\site-packages\torch\__init__.py"
    $cpu = Join-Path $pyDir "Lib\site-packages\torch\lib\c10.dll"
    $torchOk = (Test-Path -LiteralPath $init) -and (Test-Path -LiteralPath $cpu)
  }
  if (-not $torchOk) { return $false }
  if ((Test-Path -LiteralPath $m55) -and ((Get-Item $m55).Length -gt 1000000)) { return $true }
  if ((Test-Path -LiteralPath $m5) -and ((Get-Item $m5).Length -gt 1000000)) { return $true }
  return $false
}

function Test-SileroReadyAscii([string]$Root) {
  if ($Root -notmatch '^[\x00-\x7F]+$') { return $false }
  return Test-SileroFiles $Root
}

function Step($m) { Write-Host ("STEP:" + $m); Write-Host ("==> " + $m) -ForegroundColor Cyan }

if (Test-SileroReadyAscii $Tts) {
  Set-Content -LiteralPath $Marker -Value ("silero=present`n" + (Get-Date -Format o)) -Encoding ASCII
  Write-Host "OK Silero already installed: $Tts" -ForegroundColor Green
  exit 0
}

$bundledRoot = Join-Path $Root "resources\tts"
if (Test-SileroFiles $bundledRoot) {
  Step "copy-bundled"
  Write-Host "Copying bundled Silero to $Tts (no download)"
  if (Test-Path -LiteralPath $Runtime) {
    $rtItem = Get-Item -LiteralPath $Runtime -Force -ErrorAction SilentlyContinue
    if ($rtItem -and ($rtItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
      cmd /c "rmdir `"$Runtime`""
    }
  }
  New-Item -ItemType Directory -Force -Path $Tts, $Runtime, $Models | Out-Null
  $rcArgs = @(
    $bundledRoot, $Tts, "/E", "/NFL", "/NDL", "/NJH", "/NJS", "/nc", "/ns", "/np",
    "/XD", "__pycache__", "xtts_v2", "/XF", "*.whl"
  )
  & robocopy.exe @rcArgs | Out-Null
  if ($LASTEXITCODE -ge 8) {
    Write-Host ("robocopy warning exit=" + $LASTEXITCODE)
  }
  foreach ($name in @("speak.py", "tts_daemon.py", "preview.txt")) {
    $src = Join-Path $bundledRoot $name
    if (Test-Path -LiteralPath $src) {
      Copy-Item -LiteralPath $src -Destination (Join-Path $Tts $name) -Force
    }
  }
  if (Test-SileroReadyAscii $Tts) {
    Set-Content -LiteralPath $Marker -Value ("silero=copied`n" + (Get-Date -Format o)) -Encoding ASCII
    Write-Host "OK Silero ready (copied from package): $Tts" -ForegroundColor Green
    exit 0
  }
  Write-Host "Bundled copy incomplete - will try download"
}

function Download-FileAny([string[]]$Urls, [string]$OutPath, [long]$MinBytes = 1000000) {
  Invoke-JarvisDownloadAny -Urls $Urls -OutPath $OutPath -MinBytes $MinBytes -RetriesPerUrl 4 -MaxTimeSec 3600
}

function Remove-CudaTorchLeftover {
  $torchDir = Join-Path $PyDir "Lib\site-packages\torch"
  $cudaDll = Join-Path $torchDir "lib\c10_cuda.dll"
  if (Test-Path -LiteralPath $cudaDll) {
    Write-Host "  removing CUDA torch leftover (CPU wheel only)"
    Remove-Item -LiteralPath $torchDir -Recurse -Force -ErrorAction SilentlyContinue
  }
}

function Test-TorchInstalled {
  if (-not (Test-Path -LiteralPath $PyExe)) { return $false }
  if (Get-Command Apply-JarvisPythonRuntime -ErrorAction SilentlyContinue) {
    Apply-JarvisPythonRuntime $PyDir
  }
  if (Get-Command Test-JarvisTorchTree -ErrorAction SilentlyContinue) {
    if (-not (Test-JarvisTorchTree $PyDir)) { return $false }
  }
  $probe = & $PyExe -c "import torch; assert not getattr(torch.version,'cuda',None); x=torch.zeros(1); print(torch.__version__, str(x.device))" 2>$null
  $ver = [string]$probe
  return ($LASTEXITCODE -eq 0 -and $ver.Trim().Length -gt 0)
}

function Install-TorchCpu {
  $env:PIP_DEFAULT_TIMEOUT = "600"
  $env:PIP_DISABLE_PIP_VERSION_CHECK = "1"
  $trusted = @(
    "--trusted-host", "pypi.org",
    "--trusted-host", "files.pythonhosted.org",
    "--trusted-host", "pypi.python.org",
    "--trusted-host", "download.pytorch.org",
    "--trusted-host", "mirrors.aliyun.com",
    "--trusted-host", "mirror.sjtu.edu.cn",
    "--trusted-host", "npmmirror.com"
  )
  $base = @("-m", "pip", "install", "--no-warn-script-location", "--upgrade") + $trusted
  $attempts = @(
    @{ Name = "pytorch.org/cpu"; Args = $base + @("--index-url", "https://download.pytorch.org/whl/cpu", "torch") },
    @{ Name = "pytorch.org/cpu extra pypi"; Args = $base + @("--index-url", "https://download.pytorch.org/whl/cpu", "--extra-index-url", "https://pypi.org/simple", "torch") },
    @{ Name = "aliyun pytorch-wheels"; Args = $base + @("torch", "-f", "https://mirrors.aliyun.com/pytorch-wheels/cpu/torch_stable.html") },
    @{ Name = "sjtu pytorch-wheels"; Args = $base + @("torch", "-f", "https://mirror.sjtu.edu.cn/pytorch-wheels/cpu/torch_stable.html") }
  )
  $errs = @()
  foreach ($a in $attempts) {
    if (Test-TorchInstalled) { return }
    Write-Host ("  torch via " + $a.Name)
    & $PyExe @($a.Args)
    if ($LASTEXITCODE -eq 0 -and (Test-TorchInstalled)) { return }
    $errs += ($a.Name + " exit=" + $LASTEXITCODE)
  }
  throw ("torch install failed on all CPU mirrors. Often blocked in RU - enable VPN and retry. Details: " + ($errs -join "; "))
}

Step "python"
if (-not (Test-Path $PyExe)) {
  $zip = Join-Path $Runtime "python-3.11.9-embed-amd64.zip"
  Download-FileAny $PyZipUrls $zip 5000000
  if (Test-Path -LiteralPath $PyDir) {
    Get-ChildItem -LiteralPath $PyDir -Force -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -ne "." -and $_.Name -ne ".." } |
      Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
  }
  New-Item -ItemType Directory -Force -Path $PyDir | Out-Null
  Expand-Archive -LiteralPath $zip -DestinationPath $PyDir -Force
}
if (-not (Test-Path $PyExe)) { throw "python.exe missing after extract" }
if (Get-Command Apply-JarvisPythonRuntime -ErrorAction SilentlyContinue) {
  Apply-JarvisPythonRuntime $PyDir
}

$pth = Get-ChildItem $PyDir -Filter "python*._pth" | Select-Object -First 1
if ($pth) {
  $lines = @(Get-Content -LiteralPath $pth.FullName)
  $out = @()
  $hasImport = $false
  $hasLib = $false
  $hasSite = $false
  foreach ($line in $lines) {
    if ($line -match '^\s*#\s*import\s+site') {
      $out += "import site"
      $hasImport = $true
    } elseif ($line -match '^\s*import\s+site') {
      $out += "import site"
      $hasImport = $true
    } else {
      $out += $line
    }
    if ($line -match '^\s*Lib\\site-packages\s*$' -or $line -match '^\s*Lib/site-packages\s*$') { $hasSite = $true }
    if ($line -match '^\s*Lib\s*$') { $hasLib = $true }
  }
  if (-not $hasLib) { $out += "Lib" }
  if (-not $hasSite) { $out += "Lib\site-packages" }
  if (-not $hasImport) { $out += "import site" }
  Set-Content -LiteralPath $pth.FullName -Value $out -Encoding ASCII
}

Step "pip"
$getPip = Join-Path $Runtime "get-pip.py"
if (-not (Test-Path (Join-Path $PyDir "Scripts\pip.exe"))) {
  Download-FileAny $GetPipUrls $getPip 8000
  & $PyExe $getPip --no-warn-script-location
  if ($LASTEXITCODE -ne 0) { throw "get-pip failed (exit $LASTEXITCODE). Check internet/VPN." }
}

Step "torch"
Remove-CudaTorchLeftover
& $PyExe -m pip install --no-warn-script-location --upgrade pip setuptools wheel `
  --trusted-host pypi.org --trusted-host files.pythonhosted.org --trusted-host pypi.python.org
if ($LASTEXITCODE -ne 0) {
  Write-Host "pip upgrade warning - continue"
}
Install-TorchCpu

Step "numpy"
& $PyExe -m pip install --no-warn-script-location numpy `
  --trusted-host pypi.org --trusted-host files.pythonhosted.org --trusted-host pypi.python.org
if ($LASTEXITCODE -ne 0) { throw "numpy install failed" }
if (-not (Test-TorchInstalled)) {
  throw "torch import broke after numpy. Enable VPN and retry Silero download."
}

Step "model"
Download-FileAny $UrlV55List $ModelPreferred 1000000
if (-not (Test-Path $ModelPreferred) -or ((Get-Item $ModelPreferred).Length -lt 1000000)) {
  Step "model-fallback"
  Download-FileAny $UrlV5List $ModelFallback 1000000
}

$useModel = $ModelPreferred
if (-not (Test-Path $useModel) -or ((Get-Item $useModel).Length -lt 1000000)) {
  $useModel = $ModelFallback
}
if (-not (Test-Path $useModel) -or ((Get-Item $useModel).Length -lt 1000000)) {
  throw "Silero model missing after download (models.silero.ai blocked?). Enable VPN and retry."
}

Step "smoke"
$smokeTxt = Join-Path $Runtime "smoke.txt"
$smokeWav = Join-Path $Runtime "smoke.wav"
# Silero RU rejects Latin-only text (empty ValueError). Smoke must be Cyrillic.
$hi = -join [char[]](0x041F, 0x0440, 0x0438, 0x0432, 0x0435, 0x0442)
$jarvis = -join [char[]](0x0414, 0x0436, 0x0430, 0x0440, 0x0432, 0x0438, 0x0441)
$silero = -join [char[]](0x0421, 0x0438, 0x043B, 0x0435, 0x0440, 0x043E)
$smokeBody = "$hi, $jarvis. $silero OK."
[IO.File]::WriteAllText($smokeTxt, $smokeBody, [Text.UTF8Encoding]::new($false))
$speak = Join-Path $Tts "speak.py"
& $PyExe $speak --text-file $smokeTxt --out $smokeWav --voice aidar --speed 1.0 --model $useModel --sample-rate 48000
if ($LASTEXITCODE -ne 0) { throw "Silero smoke failed" }
if (-not (Test-Path $smokeWav) -or ((Get-Item $smokeWav).Length -lt 1000)) {
  throw "Silero smoke WAV missing"
}

Set-Content -LiteralPath $Marker -Value ("silero=" + (Split-Path -Leaf $useModel) + "`n" + (Get-Date -Format o)) -Encoding ASCII
Write-Host "OK Silero ready: $useModel" -ForegroundColor Green
