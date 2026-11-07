# JARVIS TTS: local Silero (v5_5_ru) primary; optional Fish Audio if Silero missing + key set.
# ASCII-only (Cyrillic in UTF-8 sidecar / TextFile). Esc stops. Up to MaxWords.
param(
    [string]$Text = "",
    [string]$TextFile = "",
    [string]$Voice = "",
    [double]$Speed = 0,
    [switch]$Preview,
    [switch]$NoInterrupt,
    [string]$OutMp3 = "",
    [string]$PlayMp3 = "",
    [int]$MaxWords = 6000
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_jarvis-data-dir.ps1")
. (Join-Path $PSScriptRoot "_jarvis-hidden-process.ps1")
. (Join-Path $PSScriptRoot "_jarvis-selection-copy.ps1")
$pyEnvHelper = Join-Path $PSScriptRoot "_jarvis-python-env.ps1"
if (Test-Path -LiteralPath $pyEnvHelper) { . $pyEnvHelper }
Add-Type -AssemblyName System.Windows.Forms

$AppRoot = $null
if ($PSScriptRoot) {
    $cand = Resolve-Path (Join-Path $PSScriptRoot "..\..") -ErrorAction SilentlyContinue
    if ($cand) { $AppRoot = $cand.Path }
}
if (-not $AppRoot) { $AppRoot = (Get-Location).Path }

function Test-TtsRootReady([string]$Root) {
    if ([string]::IsNullOrWhiteSpace($Root)) { return $false }
    # Embeddable Python + torch break on Cyrillic install paths.
    if ($Root -notmatch '^[\x00-\x7F]+$') { return $false }
    $rt = Join-Path $Root "runtime"
    $rootItem = Get-Item -LiteralPath $Root -Force -ErrorAction SilentlyContinue
    $rtItem = Get-Item -LiteralPath $rt -Force -ErrorAction SilentlyContinue
    if ($rootItem -and ($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) { return $false }
    if ($rtItem -and ($rtItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) { return $false }
    $py = Join-Path $Root "runtime\python\python.exe"
    $sp = Join-Path $Root "speak.py"
    $m55 = Join-Path $Root "models\v5_5_ru.pt"
    $m5 = Join-Path $Root "models\v5_ru.pt"
    $pyDir = Join-Path $Root "runtime\python"
    if (-not (Test-Path -LiteralPath $py)) { return $false }
    if (-not (Test-Path -LiteralPath $sp)) { return $false }
    $torchOk = $false
    if (Get-Command Test-JarvisTorchTree -ErrorAction SilentlyContinue) {
        $torchOk = Test-JarvisTorchTree $pyDir
    } else {
        $torch = Join-Path $pyDir "Lib\site-packages\torch\__init__.py"
        $cpu = Join-Path $pyDir "Lib\site-packages\torch\lib\c10.dll"
        $torchOk = (Test-Path -LiteralPath $torch) -and (Test-Path -LiteralPath $cpu)
        if (-not $torchOk) {
            $c = @(Get-ChildItem -LiteralPath (Join-Path $pyDir "Lib\site-packages\torch") -Filter "_C*.pyd" -ErrorAction SilentlyContinue)
            $torchOk = (Test-Path -LiteralPath $torch) -and ($c.Count -gt 0)
        }
    }
    if (-not $torchOk) { return $false }
    if ((Test-Path -LiteralPath $m55) -and ((Get-Item $m55).Length -gt 1000000)) { return $true }
    if ((Test-Path -LiteralPath $m5) -and ((Get-Item $m5).Length -gt 1000000)) { return $true }
    return $false
}

# ProgramData first: fetch always installs there (writable on any PC, ASCII path).
# Skip Program Files CUDA leftovers even if torch\__init__.py exists.
$pd = $env:ProgramData
if ([string]::IsNullOrWhiteSpace($pd)) { $pd = "C:\ProgramData" }
$TtsCandidates = @(
    (Join-Path $pd "JARVIS\tts"),
    (Join-Path $AppRoot "resources\tts"),
    (Join-Path $pd "JARVIS\runtime-backup\resources\tts")
)
$TtsRoot = $null
foreach ($cand in $TtsCandidates) {
    if (Test-TtsRootReady $cand) { $TtsRoot = $cand; break }
}
if (-not $TtsRoot) {
    # Other PC / Cyrillic user folder: torch dies on Unicode paths. Seed ASCII ProgramData.
    $bundledTts = Join-Path $AppRoot "resources\tts"
    $asciiDest = $TtsCandidates[0]
    $bundledPy = Join-Path $bundledTts "runtime\python\python.exe"
    $bundledModel = Join-Path $bundledTts "models\v5_5_ru.pt"
    if ((Test-Path -LiteralPath $bundledPy) -and (Test-Path -LiteralPath $bundledModel)) {
        try {
            New-Item -ItemType Directory -Force -Path $asciiDest | Out-Null
            $rt = Join-Path $asciiDest "runtime"
            if (Test-Path -LiteralPath $rt) {
                $rtItem = Get-Item -LiteralPath $rt -Force -ErrorAction SilentlyContinue
                if ($rtItem -and ($rtItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                    cmd /c "rmdir `"$rt`""
                }
            }
            & robocopy.exe $bundledTts $asciiDest /E /NFL /NDL /NJH /NJS /nc /ns /np /XD __pycache__ xtts_v2 /XF *.whl | Out-Null
        } catch {}
        if (Test-TtsRootReady $asciiDest) { $TtsRoot = $asciiDest }
    }
}
# Never point at an incomplete ProgramData tree (model-only leftover).
if (-not $TtsRoot) {
    try {
        New-Item -ItemType Directory -Force -Path (Get-JarvisDataDir) | Out-Null
        $errPath = Join-Path (Get-JarvisDataDir) "tts-last-error.txt"
        $line = "[{0}] Local Silero not ready (need ProgramData\JARVIS\tts or resources\tts with python+torch+model)." -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        Set-Content -LiteralPath $errPath -Value $line -Encoding UTF8
    } catch {}
}
if ($TtsRoot) {
    foreach ($name in @("speak.py", "tts_daemon.py")) {
        $src = Join-Path $AppRoot ("resources\tts\" + $name)
        $dst = Join-Path $TtsRoot $name
        if ((Test-Path -LiteralPath $src) -and (Test-Path -LiteralPath (Split-Path -Parent $dst))) {
            try { Copy-Item -LiteralPath $src -Destination $dst -Force } catch {}
        }
    }
    if (Get-Command Apply-JarvisPythonRuntime -ErrorAction SilentlyContinue) {
        Apply-JarvisPythonRuntime (Join-Path $TtsRoot "runtime\python")
    } else {
        $env:PYTHONHOME = $null
        $env:PYTHONPATH = $null
        $env:PYTHONNOUSERSITE = "1"
    }
} else {
    $env:PYTHONHOME = $null
    $env:PYTHONPATH = $null
    $env:PYTHONNOUSERSITE = "1"
    $TtsRoot = ""
}

$PyExe = Join-Path $TtsRoot "runtime\python\python.exe"
$SpeakPy = Join-Path $TtsRoot "speak.py"
$Model55 = Join-Path $TtsRoot "models\v5_5_ru.pt"
$Model5 = Join-Path $TtsRoot "models\v5_ru.pt"
$Ready = Join-Path $TtsRoot "runtime\.ready"

$DataDir = Get-JarvisDataDir
$StopFile = Join-Path $DataDir "tts.stop"
$CancelFile = Join-Path $DataDir "tts.cancel"
$PidFile = Join-Path $DataDir "tts.pid"
$SpeakingFile = Join-Path $DataDir "tts.speaking"
$IgnoreUntilFile = Join-Path $DataDir "tts.ignore_until"
$WorkDir = Join-Path $env:TEMP ("jarvis-tts-" + [guid]::NewGuid().ToString("N"))
$SettingsDb = Join-Path $DataDir "app.db"

function Set-TtsSpeaking([bool]$on, [int]$ExtraMs = 1200) {
    try {
        New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
        if ($on) {
            Set-Content -LiteralPath $SpeakingFile -Value "1" -Encoding ASCII
            $until = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() + [Math]::Max(2500, $ExtraMs)
            Set-Content -LiteralPath $IgnoreUntilFile -Value "$until" -Encoding ASCII
        } else {
            Remove-Item -LiteralPath $SpeakingFile -Force -ErrorAction SilentlyContinue
            $until = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() + [Math]::Max(800, $ExtraMs)
            Set-Content -LiteralPath $IgnoreUntilFile -Value "$until" -Encoding ASCII
        }
    } catch {}
}

function Extend-TtsMute([int]$Ms) {
    try {
        New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
        $until = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() + [Math]::Max(500, $Ms)
        Set-Content -LiteralPath $IgnoreUntilFile -Value "$until" -Encoding ASCII
        if (-not (Test-Path -LiteralPath $SpeakingFile)) {
            Set-Content -LiteralPath $SpeakingFile -Value "1" -Encoding ASCII
        }
    } catch {}
}

try {
    # Always clear stale Esc flags from a previous utterance.
    # -NoInterrupt only means "don't kill other tts-speak processes".
    Remove-Item -LiteralPath $CancelFile -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $StopFile -Force -ErrorAction SilentlyContinue
    if (-not $NoInterrupt) {
        # Prefer pid-file kill - full WMI scan of powershell.exe is multi-second
        # and makes the first speak after Esc feel broken.
        if (Test-Path -LiteralPath $PidFile) {
            $oldPid = 0
            if ([int]::TryParse(((Get-Content -LiteralPath $PidFile -Raw -ErrorAction SilentlyContinue).Trim()), [ref]$oldPid) -and $oldPid -gt 0 -and $oldPid -ne $PID) {
                Stop-Process -Id $oldPid -Force -ErrorAction SilentlyContinue
            }
            Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
        }
    }
} catch {}

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class JarvisTtsNative {
  [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vKey);
}
"@ -ErrorAction SilentlyContinue

# Drain sticky Esc "was pressed" bit after type is loaded.
try { [void][JarvisTtsNative]::GetAsyncKeyState(0x1B) } catch {}

function Read-TtsSettings {
    $speed = 1.0
    $volume = 1.0
    $voice = "aidar"
    $engine = "local"
    $fishKey = ""
    $openaiKey = ""
    $llmBase = "https://openrouter.ai/api/v1"
    $fishVoiceId = "0c7fd46820854a9e8c4010d911687b7a"
    $fishModel = "s2.1-pro-free"
    $mode = "ondemand"
    if (Test-Path -LiteralPath $SettingsDb) {
        try {
            $json = Get-Content -LiteralPath $SettingsDb -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -ne $json.tts_speed -and "$($json.tts_speed)" -ne "") {
                $speed = [double]$json.tts_speed
            }
            if ($json.tts_voice) {
                $voice = ([string]$json.tts_voice).Trim().ToLowerInvariant()
            }
            if ($json.tts_engine) {
                $engine = ([string]$json.tts_engine).Trim().ToLowerInvariant()
            }
            if ($json.tts_mode) {
                $m = ([string]$json.tts_mode).Trim().ToLowerInvariant()
                if ($m -eq "background" -or $m -eq "ondemand") { $mode = $m }
            }
            if ($null -ne $json.assistant_volume -and "$($json.assistant_volume)" -ne "") {
                $pct = [double]$json.assistant_volume
                if ($pct -lt 0) { $pct = 0 }
                if ($pct -gt 100) { $pct = 100 }
                $volume = $pct / 100.0
            }
            if ($json.api_keys -and $json.api_keys.fish) {
                $fishKey = [string]$json.api_keys.fish
            }
            if ($json.api_keys -and $json.api_keys.openai) {
                $openaiKey = [string]$json.api_keys.openai
            }
            if ($json.llm_base_url) {
                $llmBase = ([string]$json.llm_base_url).Trim().TrimEnd("/")
            }
            if ($json.fish_voice_id) {
                $fishVoiceId = ([string]$json.fish_voice_id).Trim()
            }
            if ($json.fish_tts_model) {
                $fishModel = ([string]$json.fish_tts_model).Trim().ToLowerInvariant()
            }
        } catch {}
    }
    if (@("aidar", "baya", "kseniya", "xenia", "eugene") -notcontains $voice) {
        if ($voice -eq "jarvis" -or $voice -eq "luna") { $voice = "aidar" }
        else { $voice = "aidar" }
    }
    if (@("cloud", "fish") -contains $engine) { $engine = "cloud" } else { $engine = "local" }
    if ([string]::IsNullOrWhiteSpace($fishVoiceId)) {
        $fishVoiceId = "0c7fd46820854a9e8c4010d911687b7a"
    }
    if (@("s1", "s2-pro", "s2.1-pro", "s2.1-pro-free") -notcontains $fishModel) {
        $fishModel = "s2.1-pro-free"
    }
    if ([string]::IsNullOrWhiteSpace($llmBase)) {
        $llmBase = "https://openrouter.ai/api/v1"
    }
    $lowBase = $llmBase.ToLowerInvariant()
    $lowKey = $openaiKey.Trim().ToLowerInvariant()
    if ($lowBase -notmatch "openrouter\.ai|api\.openai\.com") {
        if ($lowKey.StartsWith("sk-or-") -or $lowKey.Contains("openrouter")) {
            $llmBase = "https://openrouter.ai/api/v1"
        }
    }
    return @{
        Speed = $speed
        Volume = $volume
        Voice = $voice
        Engine = $engine
        Mode = $mode
        FishKey = $fishKey.Trim()
        OpenaiKey = $openaiKey.Trim()
        LlmBase = $llmBase
        FishVoiceId = $fishVoiceId
        FishModel = $fishModel
    }
}

function Clear-StopFlag {
    Remove-Item -LiteralPath $StopFile -Force -ErrorAction SilentlyContinue
}

function Request-CancelAll {
    New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
    Set-Content -LiteralPath $CancelFile -Value "1" -Encoding ASCII
    Set-Content -LiteralPath $StopFile -Value "1" -Encoding ASCII
}

function Test-ShouldStop {
    if (Test-Path -LiteralPath $CancelFile) { return $true }
    if (Test-Path -LiteralPath $StopFile) { return $true }
    try {
        # Only 0x8000 = key currently down.
        # Do NOT use 0x0001 (sticky "was pressed") - after Esc that bit stays set
        # until GetAsyncKeyState is sampled, and the next speak cancels instantly.
        $state = [JarvisTtsNative]::GetAsyncKeyState(0x1B)
        if (($state -band 0x8000) -ne 0) {
            Request-CancelAll
            return $true
        }
    } catch {}
    return $false
}

function Write-TtsError([string]$msg) {
    try {
        New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
        $path = Join-Path $DataDir "tts-last-error.txt"
        $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg
        Set-Content -LiteralPath $path -Value $line -Encoding UTF8
    } catch {}
}

function Test-SileroReady {
    if ([string]::IsNullOrWhiteSpace($TtsRoot)) { return $false }
    if (Test-TtsRootReady $TtsRoot) { return $true }
    # Daemon already loaded the model - do not fail the speak path on a flaky torch listing.
    try { if (Test-DaemonAlive) { return $true } } catch {}
    $py = Join-Path $TtsRoot "runtime\python\python.exe"
    $sp = Join-Path $TtsRoot "speak.py"
    if (-not (Test-Path -LiteralPath $py)) { return $false }
    if (-not (Test-Path -LiteralPath $sp)) { return $false }
    if ((Test-Path -LiteralPath $Model55) -and ((Get-Item $Model55).Length -gt 1000000)) { return $true }
    if ((Test-Path -LiteralPath $Model5) -and ((Get-Item $Model5).Length -gt 1000000)) { return $true }
    return $false
}

function Get-SileroModel {
    if ((Test-Path -LiteralPath $Model55) -and ((Get-Item $Model55).Length -gt 1000000)) { return $Model55 }
    return $Model5
}

function Play-Audio([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return }
    if (-not (Test-Path -LiteralPath $path)) { return }
    if (Test-ShouldStop) { return }
    $vol = 1.0
    try {
        $fresh = Read-TtsSettings
        $vol = [double]$fresh.Volume
        $script:TtsVolume = $vol
    } catch {
        try { if ($null -ne $script:TtsVolume) { $vol = [double]$script:TtsVolume } } catch { $vol = 1.0 }
    }
    if ($vol -lt 0) { $vol = 0 }
    if ($vol -gt 1) { $vol = 1 }

    $full = (Get-Item -LiteralPath $path).FullName
    $ext = [IO.Path]::GetExtension($full).ToLowerInvariant()

    # WAV: SoundPlayer then WinMM PlaySoundW. Never MediaPlayer for .wav —
    # it often never opens NaturalDuration and "plays" 2.5s of silence.
    if ($ext -eq ".wav") {
        try {
            Add-Type -AssemblyName System.Windows.Extensions -ErrorAction SilentlyContinue | Out-Null
            $sp = New-Object System.Media.SoundPlayer
            $sp.SoundLocation = $full
            $sp.Load()
            if (Test-ShouldStop) { return }
            $sp.PlaySync()
            return
        } catch {
            Write-TtsError ("SoundPlayer WAV failed: " + $_.Exception.Message)
        }
        try {
            if (-not ("JarvisWinMmPlay" -as [type])) {
                Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class JarvisWinMmPlay {
  [DllImport("winmm.dll", CharSet = CharSet.Unicode)]
  public static extern bool PlaySound(string pszSound, IntPtr hmod, uint fdwSound);
  public const uint SND_SYNC = 0x0000;
  public const uint SND_FILENAME = 0x00020000;
  public const uint SND_NODEFAULT = 0x0002;
}
"@
            }
            if (Test-ShouldStop) { return }
            $ok = [JarvisWinMmPlay]::PlaySound(
                $full,
                [IntPtr]::Zero,
                [JarvisWinMmPlay]::SND_SYNC -bor [JarvisWinMmPlay]::SND_FILENAME -bor [JarvisWinMmPlay]::SND_NODEFAULT
            )
            if ($ok) { return }
            Write-TtsError "PlaySoundW returned false"
        } catch {
            Write-TtsError ("WinMM WAV failed: " + $_.Exception.Message)
        }
        return
    }

    try {
        Add-Type -AssemblyName PresentationCore -ErrorAction Stop
        $mp = New-Object System.Windows.Media.MediaPlayer
        $mp.Volume = $vol
        $uri = New-Object System.Uri $full
        $mp.Open($uri)
        $opened = $false
        $deadline = (Get-Date).AddSeconds(8)
        while ((Get-Date) -lt $deadline) {
            if ($mp.NaturalDuration.HasTimeSpan) { $opened = $true; break }
            Start-Sleep -Milliseconds 30
            if (Test-ShouldStop) { $mp.Close(); return }
        }
        if (-not $opened) {
            Write-TtsError "MediaPlayer never opened duration for $full"
            try { $mp.Close() } catch {}
            return
        }
        $dur = [int]($mp.NaturalDuration.TimeSpan.TotalMilliseconds + 200)
        Extend-TtsMute ($dur + 800)
        $mp.Play()
        $sw = [Diagnostics.Stopwatch]::StartNew()
        while ($sw.ElapsedMilliseconds -lt $dur) {
            if (Test-ShouldStop) {
                try { $mp.Stop() } catch {}
                break
            }
            Start-Sleep -Milliseconds 25
        }
        try { $mp.Close() } catch {}
    } catch {
        Write-TtsError ("Play-Audio failed: " + $_.Exception.Message)
    }
}

function Format-TtsSpeed([double]$Rate) {
    # Always ASCII dot - Russian Windows would otherwise emit "0,75" and break Python.
    return [string]::Format([Globalization.CultureInfo]::InvariantCulture, "{0:0.##}", $Rate)
}

function Invoke-SileroSpeak([string]$TextToSpeak, [string]$Speaker, [double]$Rate, [string]$SaveAs = "") {
    if ([string]::IsNullOrWhiteSpace($TtsRoot) -or -not (Test-Path -LiteralPath $PyExe)) {
        Write-TtsError "Silero python missing - reinstall Setup or run Settings > download Silero."
        return $false
    }
    $model = Get-SileroModel
    New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
    $txt = Join-Path $WorkDir "in.txt"
    [IO.File]::WriteAllText($txt, $TextToSpeak, [Text.UTF8Encoding]::new($false))
    $speedArg = Format-TtsSpeed $Rate

    # Start-Process needs quotes on spaced paths; Start-JarvisHiddenProcess quotes itself — do not Q() there.
    function Q([string]$p) { return ('"{0}"' -f $p) }

    if (-not [string]::IsNullOrWhiteSpace($SaveAs)) {
        $outPath = $SaveAs
        if ($outPath -match '\.mp3$') { $outPath = ($outPath -replace '\.mp3$', '.wav') }
        $argList = @(
            $SpeakPy, "--text-file", $txt, "--out", $outPath,
            "--voice", $Speaker, "--speed", $speedArg,
            "--model", $model, "--sample-rate", "48000", "--max-words", "$MaxWords",
            "--stop-file", $StopFile
        )
        $errFile = Join-Path $WorkDir "err.txt"
        $outFile = Join-Path $WorkDir "out.txt"
        $p = Start-JarvisHiddenProcess -FilePath $PyExe -ArgumentList $argList -Wait `
            -RedirectStandardError $errFile -RedirectStandardOutput $outFile
        if (-not $p -or $p.ExitCode -ne 0) {
            $err = ""
            try { $err = Get-Content $errFile -Raw -ErrorAction SilentlyContinue } catch {}
            Write-TtsError ("Silero generate failed: " + $err)
            return $false
        }
        if (-not (Test-Path -LiteralPath $outPath) -or ((Get-Item $outPath).Length -lt 500)) {
            Write-TtsError "Silero produced empty WAV"
            return $false
        }
        if ($outPath -ne $SaveAs -and -not [string]::IsNullOrWhiteSpace($SaveAs)) {
            try { Copy-Item -LiteralPath $outPath -Destination $SaveAs -Force } catch {}
        }
        return $true
    }

    $chunkDir = Join-Path $WorkDir "chunks"
    New-Item -ItemType Directory -Force -Path $chunkDir | Out-Null
    $argList = @(
        (Q $SpeakPy), "--text-file", (Q $txt), "--out", (Q $chunkDir), "--stream",
        "--voice", $Speaker, "--speed", $speedArg,
        "--model", (Q $model), "--sample-rate", "48000", "--max-words", "$MaxWords",
        "--stop-file", (Q $StopFile)
    )
    $stdout = Join-Path $WorkDir "stream-out.txt"
    $stderr = Join-Path $WorkDir "stream-err.txt"
    # Live stdout file for chunk READY lines. Do NOT combine -NoNewWindow with -WindowStyle
    # (PS 5.1 throws InvalidOperation and Silero never starts). Parent already has no console.
    $p = Start-Process -FilePath $PyExe -ArgumentList $argList -PassThru -NoNewWindow `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    if (-not $p) {
        Write-TtsError "Silero stream failed to start"
        return $false
    }
    $played = 0
    $deadline = (Get-Date).AddMinutes(30)
    while ((Get-Date) -lt $deadline) {
        if (Test-ShouldStop) {
            try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch {}
            break
        }
        if (Test-Path -LiteralPath $stdout) {
            $lines = @(Get-Content -LiteralPath $stdout -ErrorAction SilentlyContinue)
            foreach ($line in $lines) {
                if ($line -like "READY *") {
                    $wav = $line.Substring(6).Trim()
                    if ((Test-Path -LiteralPath $wav) -and ($wav -notin $script:PlayedWavs)) {
                        if (-not $script:PlayedWavs) { $script:PlayedWavs = @() }
                        $script:PlayedWavs += $wav
                        Play-Audio $wav
                        $played++
                    }
                } elseif ($line -eq "DONE" -or $line -eq "STOPPED") {
                    try { Wait-Process -Id $p.Id -Timeout 2 -ErrorAction SilentlyContinue } catch {}
                    return ($played -gt 0)
                }
            }
        }
        if ($p.HasExited -and $played -eq 0) {
            Start-Sleep -Milliseconds 200
            $left = @(Get-ChildItem -LiteralPath $chunkDir -Filter "chunk_*.wav" -ErrorAction SilentlyContinue | Sort-Object Name)
            foreach ($f in $left) {
                if ($f.FullName -notin $script:PlayedWavs) {
                    Play-Audio $f.FullName
                    $played++
                }
            }
            break
        }
        if ($p.HasExited) { break }
        Start-Sleep -Milliseconds 80
    }
    return ($played -gt 0)
}

function Get-TtsMode {
    # Settings DB (via $cfg) is source of truth; keep tts.mode flag in sync.
    $mode = "ondemand"
    try {
        if ($null -ne $cfg -and $cfg.Mode) {
            $m = ([string]$cfg.Mode).Trim().ToLowerInvariant()
            if ($m -eq "background") { $mode = "background" }
        }
    } catch {}
    try {
        $modeFile = Join-Path $DataDir "tts.mode"
        New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
        Set-Content -LiteralPath $modeFile -Value $mode -Encoding ASCII
    } catch {}
    return $mode
}

function Test-DaemonAlive {
    $alive = Join-Path $DataDir "tts-worker\alive"
    $pidFile = Join-Path $DataDir "tts.worker.pid"
    if (-not (Test-Path -LiteralPath $alive)) { return $false }
    if (-not (Test-Path -LiteralPath $pidFile)) { return $false }
    try {
        $ts = [int64]((Get-Content -LiteralPath $alive -Raw).Trim())
        $age = [int64]([DateTime]::UtcNow - [datetime]'1970-01-01').TotalSeconds - $ts
        if ($age -lt 0 -or $age -gt 12) { return $false }
        $wpid = 0
        if (-not [int]::TryParse((Get-Content -LiteralPath $pidFile -Raw).Trim(), [ref]$wpid)) { return $false }
        $p = Get-Process -Id $wpid -ErrorAction Stop
        return ($p -and ($p.ProcessName -match 'python'))
    } catch {
        return $false
    }
}

function Invoke-DaemonSpeak([string]$TextToSpeak, [string]$Speaker, [double]$Rate, [string]$SaveAs = "") {
    # Re-clear Esc flags right before queueing - stop.ps1 leaves them set, and a
    # slow WMI cleanup above can race with a fresh speak after Escape.
    Remove-Item -LiteralPath $CancelFile, $StopFile -Force -ErrorAction SilentlyContinue

    $inbox = Join-Path $DataDir "tts-worker\inbox"
    New-Item -ItemType Directory -Force -Path $inbox | Out-Null
    $jobId = [guid]::NewGuid().ToString("N")
    $outDir = Join-Path $WorkDir ("daemon-" + $jobId)
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    $speedNum = [double]$Rate
    if ($speedNum -lt 0.5) { $speedNum = 0.5 }
    if ($speedNum -gt 2.0) { $speedNum = 2.0 }
    $job = @{
        id = $jobId
        text = $TextToSpeak
        voice = $Speaker
        speed = $speedNum
        out_dir = $outDir
        stop_file = $StopFile
        max_words = $MaxWords
        sample_rate = 48000
    }
    # Invariant JSON - Russian locale must not emit "1,0" for speed.
    $jobJson = ($job | ConvertTo-Json -Compress -Depth 4)
    try {
        $jobJson = [regex]::Replace($jobJson, '"speed"\s*:\s*([\d]+)\,([\d]+)', '"speed":$1.$2')
    } catch {}
    $jobPath = Join-Path $inbox ($jobId + ".json")
    $donePath = Join-Path $inbox ($jobId + ".done")
    $errPath = Join-Path $inbox ($jobId + ".error")
    [IO.File]::WriteAllText($jobPath, $jobJson, [Text.UTF8Encoding]::new($false))

    $deadline = (Get-Date).AddMinutes(8)
    while ((Get-Date) -lt $deadline) {
        if (Test-ShouldStop) {
            Remove-Item -LiteralPath $jobPath,$donePath,$errPath -Force -ErrorAction SilentlyContinue
            return $false
        }
        if (Test-Path -LiteralPath $donePath) { break }
        Start-Sleep -Milliseconds 60
    }
    if (-not (Test-Path -LiteralPath $donePath)) {
        Write-TtsError "Background TTS worker timeout"
        return $false
    }
    $doneRaw = ""
    try { $doneRaw = (Get-Content -LiteralPath $donePath -Raw -ErrorAction SilentlyContinue).Trim() } catch {}
    if ($doneRaw -eq "error") {
        $err = ""
        try { $err = Get-Content -LiteralPath $errPath -Raw -ErrorAction SilentlyContinue } catch {}
        Write-TtsError ("Background TTS failed: " + $err)
        return $false
    }

    $wavs = @(Get-ChildItem -LiteralPath $outDir -Filter "chunk_*.wav" -ErrorAction SilentlyContinue | Sort-Object Name)
    if ($wavs.Count -eq 0) {
        Write-TtsError "Background TTS produced no audio"
        return $false
    }

    if (-not [string]::IsNullOrWhiteSpace($SaveAs)) {
        $outPath = $SaveAs
        if ($outPath -match '\.mp3$') { $outPath = ($outPath -replace '\.mp3$', '.wav') }
        $good = @($wavs | Where-Object { $_.Length -ge 500 })
        if ($good.Count -eq 0) {
            Write-TtsError "Background TTS empty output"
            return $false
        }
        # Multi-chunk SaveAs is unreliable for generate path - fail soft so ondemand regenerates one file.
        if ($good.Count -gt 1) {
            Write-TtsError "Background TTS multi-chunk generate - using on-demand"
            return $false
        }
        Copy-Item -LiteralPath $good[0].FullName -Destination $outPath -Force
        if ($outPath -ne $SaveAs) {
            try { Copy-Item -LiteralPath $outPath -Destination $SaveAs -Force } catch {}
        }
        return ((Test-Path -LiteralPath $outPath) -and ((Get-Item $outPath).Length -ge 500))
    }

    foreach ($w in $wavs) {
        if (Test-ShouldStop) { return $false }
        Play-Audio $w.FullName
    }
    return $true
}

function Ensure-BackgroundWorker {
    if (Test-DaemonAlive) {
        Remove-Item -LiteralPath (Join-Path $DataDir "tts-worker\loading") -Force -ErrorAction SilentlyContinue
        return $true
    }
    $ctl = Join-Path $PSScriptRoot "tts-worker-ctl.ps1"
    if (-not (Test-Path -LiteralPath $ctl)) { return $false }

    $loading = Join-Path $DataDir "tts-worker\loading"
    # Stale loading after Esc/crash: flag present but no daemon process → clear and restart.
    $daemonProc = $null
    try {
        $daemonProc = Get-CimInstance Win32_Process -Filter "Name = 'python.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -and $_.CommandLine -like "*tts_daemon.py*" } |
            Select-Object -First 1
    } catch {}
    if ((Test-Path -LiteralPath $loading) -and -not $daemonProc) {
        Remove-Item -LiteralPath $loading -Force -ErrorAction SilentlyContinue
        # Drop stale pid/alive so Test-DaemonAlive cannot flap.
        Remove-Item -LiteralPath (Join-Path $DataDir "tts.worker.pid"),(Join-Path $DataDir "tts-worker\alive") -Force -ErrorAction SilentlyContinue
    }

    $alreadyStarting = (Test-Path -LiteralPath $loading) -or ($null -ne $daemonProc)
    try {
        if (-not $alreadyStarting) {
            & $ctl -Action start 2>$null | Out-Null
        }
    } catch {}

    # Model cold-load is ~8-25s while the process is up. If start never marks loading /
    # dies immediately, fall through to on-demand quickly (do not burn 90s).
    $deadline = (Get-Date).AddSeconds(45)
    $sawLoading = (Test-Path -LiteralPath $loading) -or ($null -ne $daemonProc)
    $noProgressSince = Get-Date
    while ((Get-Date) -lt $deadline) {
        if (Test-DaemonAlive) {
            Remove-Item -LiteralPath $loading -Force -ErrorAction SilentlyContinue
            return $true
        }
        if (Test-ShouldStop) { return $false }

        $procUp = $false
        try {
            $procUp = $null -ne (Get-CimInstance Win32_Process -Filter "Name = 'python.exe'" -ErrorAction SilentlyContinue |
                Where-Object { $_.CommandLine -and $_.CommandLine -like "*tts_daemon.py*" } |
                Select-Object -First 1)
        } catch {}

        if ((Test-Path -LiteralPath $loading) -or $procUp) {
            $sawLoading = $true
            $noProgressSince = Get-Date
        } else {
            if (((Get-Date) - $noProgressSince).TotalSeconds -ge 2.5) {
                if (-not $sawLoading) {
                    try { & $ctl -Action start 2>$null | Out-Null } catch {}
                    $sawLoading = (Test-Path -LiteralPath $loading)
                    $noProgressSince = Get-Date
                    if (-not $sawLoading) { break }
                } else {
                    break
                }
            }
        }
        Start-Sleep -Milliseconds 200
    }
    return (Test-DaemonAlive)
}

function Invoke-OpenRouterSpeak([string]$TextToSpeak, [string]$ApiKey, [string]$BaseUrl, [double]$Rate, [string]$SaveAs = "") {
    if ([string]::IsNullOrWhiteSpace($ApiKey)) { return $false }
    if ($ApiKey.StartsWith("JARVISDP1:")) {
        Write-TtsError "OpenRouter key is DPAPI-sealed in app.db for PowerShell — use Rust cloud path or re-save key."
        return $false
    }
    $base = if ([string]::IsNullOrWhiteSpace($BaseUrl)) { "https://openrouter.ai/api/v1" } else { $BaseUrl.TrimEnd("/") }
    $models = if ($base.ToLowerInvariant().Contains("api.openai.com")) {
        @(@{ Model = "gpt-4o-mini-tts"; Voice = "nova" })
    } else {
        @(
            @{ Model = "fish-audio/s2.1-pro-free:free"; Voice = "0c7fd46820854a9e8c4010d911687b7a" },
            @{ Model = "fish-audio/s2.1-pro"; Voice = "0c7fd46820854a9e8c4010d911687b7a" },
            @{ Model = "x-ai/grok-voice-tts-1.0"; Voice = "eve" }
        )
    }
    $url = "$base/audio/speech"
    $tmp = Join-Path $WorkDir ("or-" + [guid]::NewGuid().ToString("N") + ".mp3")
    foreach ($m in $models) {
    try {
        $bodyObj = @{
            model = $m.Model
            input = $TextToSpeak
            voice = $m.Voice
            response_format = "mp3"
            speed = [math]::Max(0.5, [math]::Min(2.0, $Rate))
        }
        $body = $bodyObj | ConvertTo-Json -Compress
        $req = [System.Net.HttpWebRequest]::Create($url)
        $req.Method = "POST"
        $req.ContentType = "application/json"
        $req.Headers["Authorization"] = "Bearer $ApiKey"
        $req.UserAgent = "JARVIS/1.0 (Windows; CloudTTS)"
        if ($base.ToLowerInvariant().Contains("openrouter.ai")) {
            $req.Headers["HTTP-Referer"] = "https://openrouter.ai/"
            $req.Headers["X-Title"] = "JARVIS"
        }
        $bytes = [Text.Encoding]::UTF8.GetBytes($body)
        $req.ContentLength = $bytes.Length
        $stream = $req.GetRequestStream()
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Close()
        $resp = $req.GetResponse()
        $rs = $resp.GetResponseStream()
        $fs = [IO.File]::Create($tmp)
        $rs.CopyTo($fs)
        $fs.Close()
        $rs.Close()
        $resp.Close()
        if (-not (Test-Path -LiteralPath $tmp) -or ((Get-Item -LiteralPath $tmp).Length -lt 200)) {
            Write-TtsError ("OpenRouter TTS empty body model=" + $m.Model)
            continue
        }
        if (-not [string]::IsNullOrWhiteSpace($SaveAs)) {
            Copy-Item -LiteralPath $tmp -Destination $SaveAs -Force
            return $true
        }
        return $true
    } catch {
        Write-TtsError ("OpenRouter TTS failed model=" + $m.Model + ": " + $_.Exception.Message)
        continue
    }
    }
    return $false
}

function Invoke-FishSpeak([string]$TextToSpeak, [string]$ApiKey, [string]$VoiceId, [string]$Model, [double]$Rate, [string]$SaveAs = "") {
    if ([string]::IsNullOrWhiteSpace($ApiKey)) { return $false }
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    } catch {}
    New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
    $outFile = [IO.Path]::GetFullPath((Join-Path $WorkDir "fish.mp3"))
    $spd = $Rate
    if ($spd -lt 0.5) { $spd = 0.5 }
    if ($spd -gt 2.0) { $spd = 2.0 }
    $payload = @{
        text = $TextToSpeak
        reference_id = $VoiceId
        format = "mp3"
        mp3_bitrate = 64
        normalize = $true
        latency = "balanced"
        chunk_length = 100
        prosody = @{ speed = $spd; volume = 0; normalize_loudness = $true }
    }
    $jsonBody = $payload | ConvertTo-Json -Depth 6 -Compress
    $bodyBytes = [Text.Encoding]::UTF8.GetBytes($jsonBody)
    try {
        $req = [System.Net.HttpWebRequest]::Create("https://api.fish.audio/v1/tts")
        $req.Method = "POST"
        $req.ContentType = "application/json"
        $req.Accept = "*/*"
        $req.Timeout = 120000
        $req.ReadWriteTimeout = 120000
        $req.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate
        [void]$req.Headers.Add("Authorization", "Bearer " + $ApiKey)
        [void]$req.Headers.Add("model", $Model)
        $req.ContentLength = $bodyBytes.Length
        $stream = $req.GetRequestStream()
        try { $stream.Write($bodyBytes, 0, $bodyBytes.Length) } finally { $stream.Close() }
        $resp = $req.GetResponse()
        try {
            $rs = $resp.GetResponseStream()
            $fs = [IO.File]::Create($outFile)
            try {
                $buf = New-Object byte[] 8192
                while ($true) {
                    if (Test-ShouldStop) { return $false }
                    $n = $rs.Read($buf, 0, $buf.Length)
                    if ($n -le 0) { break }
                    $fs.Write($buf, 0, $n)
                }
            } finally { $fs.Close(); $rs.Close() }
        } finally { $resp.Close() }
    } catch {
        Write-TtsError ("Fish Audio API failed: " + $_.Exception.Message)
        return $false
    }
    if (-not (Test-Path -LiteralPath $outFile) -or ((Get-Item $outFile).Length -lt 200)) {
        Write-TtsError "Fish Audio empty body"
        return $false
    }
    if (-not [string]::IsNullOrWhiteSpace($SaveAs)) {
        Copy-Item -LiteralPath $outFile -Destination $SaveAs -Force
        return $true
    }
    Play-Audio $outFile
    return $true
}

# --- main ---
if (-not [string]::IsNullOrWhiteSpace($PlayMp3)) {
    if (Test-ShouldStop) { exit 0 }
    Set-Content -LiteralPath $PidFile -Value $PID -Encoding ASCII
    Set-TtsSpeaking $true 8000
    Play-Audio $PlayMp3
    Set-TtsSpeaking $false 400
    if (-not (Test-Path -LiteralPath $CancelFile)) { Clear-StopFlag }
    Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
    exit 0
}

$cfg = Read-TtsSettings
$script:TtsVolume = [double]$cfg.Volume
if ($Speed -le 0) { $Speed = [double]$cfg.Speed }
if ($Speed -lt 0.5) { $Speed = 0.5 }
if ($Speed -gt 2.0) { $Speed = 2.0 }
if ([string]::IsNullOrWhiteSpace($Voice)) { $Voice = $cfg.Voice }
$Voice = $Voice.Trim().ToLowerInvariant()
if (@("aidar", "baya", "kseniya", "xenia", "eugene") -notcontains $Voice) { $Voice = "aidar" }

$source = ""
if ($Preview) {
    $previewFile = Join-Path $TtsRoot "preview.txt"
    if (Test-Path -LiteralPath $previewFile) {
        $source = [IO.File]::ReadAllText($previewFile, [Text.Encoding]::UTF8)
    }
    if ([string]::IsNullOrWhiteSpace($source)) {
        # Silero RU rejects Latin-only text. Keep this file ASCII.
        $hi = -join [char[]](0x041F, 0x0440, 0x0438, 0x0432, 0x0435, 0x0442)
        $local = -join [char[]](0x043B, 0x043E, 0x043A, 0x0430, 0x043B, 0x044C, 0x043D, 0x0430, 0x044F)
        $ttsWord = -join [char[]](0x043E, 0x0437, 0x0432, 0x0443, 0x0447, 0x043A, 0x0430)
        $source = "$hi. $local $ttsWord Silero."
    }
} elseif (-not [string]::IsNullOrWhiteSpace($TextFile) -and (Test-Path -LiteralPath $TextFile)) {
    $source = [IO.File]::ReadAllText($TextFile, [Text.Encoding]::UTF8)
} elseif (-not [string]::IsNullOrWhiteSpace($Text)) {
    $source = $Text
} else {
    try { $source = Get-JarvisSelectionOrClipboard } catch { $source = "" }
}
$source = ($source -replace "`r`n", "`n").Trim()
if ([string]::IsNullOrWhiteSpace($source)) {
    Write-TtsError "No text to speak."
    exit 1
}

$wordMatches = [regex]::Matches($source, "\S+")
if ($wordMatches.Count -gt $MaxWords) {
    $cut = $wordMatches[$MaxWords - 1].Index + $wordMatches[$MaxWords - 1].Length
    if ($cut -gt 0 -and $cut -lt $source.Length) {
        $source = $source.Substring(0, $cut).Trim()
    }
}

$genOnly = -not [string]::IsNullOrWhiteSpace($OutMp3)
if (-not $genOnly) {
    Set-Content -LiteralPath $PidFile -Value $PID -Encoding ASCII
    $estMs = 4000 + [Math]::Min(25000, ($source.Length * 55))
    Set-TtsSpeaking $true $estMs
}

$ok = $false
$ErrorActionPreference = "Continue"
try {
    function Invoke-LocalSileroPath {
        if (-not (Test-SileroReady)) {
            Write-TtsError "Local Silero missing. Reinstall JARVIS-Setup (voice pack inside Setup) or download Silero in Settings."
            return $false
        }
        $useBg = $false
        try {
            $modeNow = Get-TtsMode
            # Only use background if worker is ALREADY warm. Never block first speak
            # for 45s+ on a cold daemon start (that feels like "озвучка мертва").
            if ($modeNow -eq "background" -and (Test-DaemonAlive)) {
                $useBg = $true
            } elseif ($modeNow -eq "background") {
                # Kick off start in background, but speak on-demand this turn.
                try {
                    $ctl = Join-Path $PSScriptRoot "tts-worker-ctl.ps1"
                    if (Test-Path -LiteralPath $ctl) {
                        Start-JarvisHiddenProcess -FilePath "powershell.exe" -ArgumentList @(
                            "-NoLogo", "-NonInteractive", "-NoProfile", "-ExecutionPolicy", "Bypass",
                            "-File", $ctl, "-Action", "start"
                        ) | Out-Null
                    }
                } catch {}
            }
        } catch {}
        if ($useBg) {
            $localOk = [bool](Invoke-DaemonSpeak -TextToSpeak $source -Speaker $Voice -Rate $Speed -SaveAs $OutMp3)
            if (-not $localOk -and -not (Test-ShouldStop)) {
                Write-TtsError "Background worker failed - falling back to on-demand load"
                $localOk = [bool](Invoke-SileroSpeak -TextToSpeak $source -Speaker $Voice -Rate $Speed -SaveAs $OutMp3)
            }
            return $localOk
        }
        return [bool](Invoke-SileroSpeak -TextToSpeak $source -Speaker $Voice -Rate $Speed -SaveAs $OutMp3)
    }

    # Prefer on-demand when background worker is cold/broken - first speak must not hang minutes.
    if ($cfg.Engine -eq "cloud") {
        $ok = $false
        if (-not [string]::IsNullOrWhiteSpace($cfg.FishKey) -and -not $cfg.FishKey.StartsWith("JARVISDP1:")) {
            $ok = [bool](Invoke-FishSpeak -TextToSpeak $source -ApiKey $cfg.FishKey -VoiceId $cfg.FishVoiceId -Model $cfg.FishModel -Rate $Speed -SaveAs $OutMp3)
            if (-not $ok -and -not (Test-ShouldStop)) {
                Write-TtsError "Fish Audio failed (401/network) - try OpenRouter key."
            }
        }
        if (-not $ok -and -not (Test-ShouldStop) -and -not [string]::IsNullOrWhiteSpace($cfg.OpenaiKey)) {
            $ok = [bool](Invoke-OpenRouterSpeak -TextToSpeak $source -ApiKey $cfg.OpenaiKey -BaseUrl $cfg.LlmBase -Rate $Speed -SaveAs $OutMp3)
            if (-not $ok -and -not (Test-ShouldStop)) {
                Write-TtsError "OpenRouter TTS failed - falling back to local Silero."
            }
        }
        if (-not $ok -and -not (Test-ShouldStop)) {
            if ([string]::IsNullOrWhiteSpace($cfg.FishKey) -and [string]::IsNullOrWhiteSpace($cfg.OpenaiKey)) {
                Write-TtsError "Cloud TTS selected but no Fish/OpenRouter key - switching to local Silero."
            }
            $ok = [bool](Invoke-LocalSileroPath)
        }
    } else {
        $ok = [bool](Invoke-LocalSileroPath)
    }
} catch {
    Write-TtsError ("TTS path crashed: " + $_.Exception.Message)
    $ok = $false
}
$ErrorActionPreference = "Stop"

if (-not $genOnly) {
    Set-TtsSpeaking $false 1800
    if (-not (Test-Path -LiteralPath $CancelFile)) { Clear-StopFlag }
    Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
}
Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue
if ($ok) {
    # Clear stale failure notes so Settings/debug don't show yesterday's error after success.
    try {
        $errPath = Join-Path $DataDir "tts-last-error.txt"
        if (Test-Path -LiteralPath $errPath) { Remove-Item -LiteralPath $errPath -Force -ErrorAction SilentlyContinue }
    } catch {}
    exit 0
}
exit 1
