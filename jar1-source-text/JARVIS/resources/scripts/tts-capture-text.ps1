# Capture UTF-8 text for TTS preview + speak (selection -> focus target window + Ctrl+C).
param(
    [string]$OutFile = "",
    [string]$PreferredFile = "",
    [switch]$ClipboardOnly
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_jarvis-data-dir.ps1")
. (Join-Path $PSScriptRoot "_jarvis-selection-copy.ps1")
Add-Type -AssemblyName System.Windows.Forms

$DataDir = Get-JarvisDataDir
New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
if ([string]::IsNullOrWhiteSpace($OutFile)) {
    $OutFile = Join-Path $DataDir "tts-capture.txt"
}

function Read-Utf8([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return "" }
    try {
        return [System.IO.File]::ReadAllText($path, [System.Text.UTF8Encoding]::new($false)).Trim()
    } catch {
        return ""
    }
}

function Write-Utf8([string]$path, [string]$text) {
    [System.IO.File]::WriteAllText($path, $text, [System.Text.UTF8Encoding]::new($false))
}

$source = ""
if (-not [string]::IsNullOrWhiteSpace($PreferredFile)) {
    $source = Read-Utf8 $PreferredFile
}

if ([string]::IsNullOrWhiteSpace($source)) {
    if ($ClipboardOnly) {
        $source = Get-JarvisClipboardTextSafe
    } else {
        $source = Get-JarvisSelectionOrClipboard -RestoreClipboard
    }
}

$triggerOnly = @{}
$triggerFile = Join-Path (Join-Path (Split-Path $PSScriptRoot) "tts") "trigger-phrases.txt"
if (-not (Test-Path -LiteralPath $triggerFile)) {
    $triggerFile = Join-Path (Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path "resources\tts") "trigger-phrases.txt"
}
if (Test-Path -LiteralPath $triggerFile) {
    foreach ($line in [System.IO.File]::ReadAllLines($triggerFile, [System.Text.UTF8Encoding]::new($false))) {
        $t = ($line.Trim().ToLower() -replace "\s+", " ")
        if (-not [string]::IsNullOrWhiteSpace($t)) { $triggerOnly[$t] = $true }
    }
}

function Test-IsTriggerLike([string]$value) {
    if ([string]::IsNullOrWhiteSpace($value)) { return $false }
    $norm = ($value.Trim().ToLower() -replace "\s+", " ")
    if ($triggerOnly.ContainsKey($norm)) { return $true }
    # Exact leftover only. "читай это завтра на работе" is real clipboard text.
    if ($norm.Length -le 24) {
        foreach ($t in $triggerOnly.Keys) {
            if ($norm -eq $t) { return $true }
        }
    }
    return $false
}

if (-not [string]::IsNullOrWhiteSpace($source) -and (Test-IsTriggerLike $source)) {
    $source = ""
    if (-not $ClipboardOnly) {
        $source = Get-JarvisSelectionOrClipboard -RestoreClipboard
    }
}

if ([string]::IsNullOrWhiteSpace($source)) {
    Write-Utf8 $OutFile ""
    exit 1
}

Write-Utf8 $OutFile $source
exit 0
