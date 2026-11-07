# Local-only HTTP bridge for TTS mode (optional helper).
# Listens on 127.0.0.1:18718 - outside JARVIS IPC band 9712-9722.
param(
    [int]$Port = 18718
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_jarvis-data-dir.ps1")
$prefix = "http://127.0.0.1:$Port/"
$setMode = Join-Path $PSScriptRoot "set-tts-mode.ps1"
$dataDir = Get-JarvisDataDir
$modeFile = Join-Path $dataDir "tts.mode"

function Get-CurrentMode {
    if (Test-Path -LiteralPath $modeFile) {
        $m = (Get-Content -LiteralPath $modeFile -Raw -ErrorAction SilentlyContinue).Trim().ToLowerInvariant()
        if ($m -eq "background") { return "background" }
    }
    return "ondemand"
}

function Set-Mode([string]$Mode) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $setMode $Mode
    if ($LASTEXITCODE -ne 0) { throw "set-tts-mode failed: $LASTEXITCODE" }
}

$existing = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -eq "powershell.exe" -and $_.CommandLine -and $_.CommandLine -like "*tts-mode-bridge.ps1*" -and $_.ProcessId -ne $PID }
foreach ($p in $existing) {
    try { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue } catch {}
}

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add($prefix)
try {
    $listener.Start()
} catch {
    exit 0
}

function Send-Response($ctx, [int]$code, [string]$body, [string]$contentType = "application/json; charset=utf-8") {
    $buf = [Text.Encoding]::UTF8.GetBytes($body)
    $ctx.Response.StatusCode = $code
    $ctx.Response.ContentType = $contentType
    $ctx.Response.Headers.Add("Access-Control-Allow-Origin", "*")
    $ctx.Response.Headers.Add("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
    $ctx.Response.Headers.Add("Access-Control-Allow-Headers", "Content-Type")
    $ctx.Response.ContentLength64 = $buf.Length
    $ctx.Response.OutputStream.Write($buf, 0, $buf.Length)
    $ctx.Response.OutputStream.Close()
}

while ($listener.IsListening) {
    $ctx = $null
    try {
        $ctx = $listener.GetContext()
        $method = $ctx.Request.HttpMethod.ToUpperInvariant()
        $path = $ctx.Request.Url.AbsolutePath.TrimEnd('/').ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($path)) { $path = "/" }

        if ($method -eq "OPTIONS") {
            Send-Response $ctx 204 ""
            continue
        }

        if ($method -eq "GET" -and ($path -eq "/" -or $path -eq "/mode")) {
            Send-Response $ctx 200 (@{ ok = $true; mode = (Get-CurrentMode) } | ConvertTo-Json -Compress)
            continue
        }

        if ($method -eq "POST" -and $path -eq "/mode") {
            $reader = New-Object IO.StreamReader($ctx.Request.InputStream, $ctx.Request.ContentEncoding)
            $raw = $reader.ReadToEnd()
            $reader.Close()
            $mode = $null
            try {
                $json = $raw | ConvertFrom-Json
                $mode = [string]$json.mode
            } catch {
                if ($raw -match "background") { $mode = "background" }
                elseif ($raw -match "ondemand") { $mode = "ondemand" }
            }
            $mode = ("$mode").Trim().ToLowerInvariant()
            if ($mode -ne "background" -and $mode -ne "ondemand") {
                Send-Response $ctx 400 (@{ ok = $false; error = "mode must be ondemand|background" } | ConvertTo-Json -Compress)
                continue
            }
            Set-Mode $mode
            Send-Response $ctx 200 (@{ ok = $true; mode = $mode } | ConvertTo-Json -Compress)
            continue
        }

        Send-Response $ctx 404 (@{ ok = $false; error = "not found" } | ConvertTo-Json -Compress)
    } catch {
        if ($ctx) {
            try { Send-Response $ctx 500 (@{ ok = $false; error = $_.Exception.Message } | ConvertTo-Json -Compress) } catch {}
        }
        Start-Sleep -Milliseconds 200
    }
}
