# Ensures Vosk can load when JARVIS lives under a non-ASCII path
# (Cyrillic username / Desktop / D:\РусскаяПапка). Vosk/Kaldi cannot open those paths.
param(
    [Parameter(Mandatory = $true)]
    [string]$AppDir
)

$ErrorActionPreference = "Stop"
$AppDir = [IO.Path]::GetFullPath($AppDir)
$src = Join-Path $AppDir "resources\vosk\vosk-model-small-ru-0.22"
$srcMdl = Join-Path $src "am\final.mdl"

if (-not (Test-Path -LiteralPath $srcMdl)) {
    exit 0
}

function Test-AsciiPath([string]$Path) {
    return ($Path -match '^[\x00-\x7F]+$')
}

if (Test-AsciiPath $src) {
    exit 0
}

$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
# Per-user SID keeps concurrent users/installations from deleting each other's
# mirror while retaining an ASCII-only path independent of the profile name.
$programData = $env:ProgramData
if ([string]::IsNullOrWhiteSpace($programData)) { $programData = "C:\ProgramData" }
$destRoot = Join-Path $programData "JARVIS\users\$sid\vosk"
$dest = Join-Path $destRoot "vosk-model-small-ru-0.22"
$stamp = Join-Path $destRoot "vosk-model-small-ru-0.22.stamp"
$srcLen = (Get-Item -LiteralPath $srcMdl).Length
$srcHash = (Get-FileHash -LiteralPath $srcMdl -Algorithm SHA256).Hash

$reuse = $false
if ((Test-Path -LiteralPath (Join-Path $dest "am\final.mdl")) -and (Test-Path -LiteralPath $stamp)) {
    $lines = Get-Content -LiteralPath $stamp -ErrorAction SilentlyContinue
    if ($lines.Count -ge 3 -and $lines[0] -eq $src -and $lines[1] -eq "$srcLen" -and $lines[2] -eq $srcHash) {
        $reuse = $true
    }
}

if (-not $reuse) {
    New-Item -ItemType Directory -Path $destRoot -Force | Out-Null
    $temp = "$dest.new-$PID"
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $temp -Force | Out-Null
    cmd /c "robocopy `"$src`" `"$temp`" /E /R:2 /W:2 /NFL /NDL /NJH /NJS /nc /ns /np >nul"
    if ($LASTEXITCODE -ge 8) {
        Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
        Write-Error "Failed to mirror Vosk model to $dest (robocopy $LASTEXITCODE)"
        exit 1
    }
    $copiedMdl = Join-Path $temp "am\final.mdl"
    if ((Get-FileHash -LiteralPath $copiedMdl -Algorithm SHA256).Hash -ne $srcHash) {
        Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
        Write-Error "Vosk mirror SHA256 verification failed"
        exit 1
    }
    if (Test-Path -LiteralPath $dest) {
        Remove-Item -LiteralPath $dest -Recurse -Force
    }
    Move-Item -LiteralPath $temp -Destination $dest
    @(
        $src
        "$srcLen"
        $srcHash
    ) | Set-Content -LiteralPath $stamp -Encoding ASCII
}

# Expose ASCII path to jarvis-app (picked up by get_configured_model_path).
[Environment]::SetEnvironmentVariable("JARVIS_VOSK_MODEL", $dest, "Process")
Write-Output $dest
exit 0
