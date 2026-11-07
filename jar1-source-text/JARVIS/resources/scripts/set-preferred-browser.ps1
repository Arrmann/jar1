param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet("chrome", "yandex", "edge", "firefox", "opera", "brave", "default")]
    [string]$Browser
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_jarvis-data-dir.ps1")

function Assert-BrowserAvailable([string]$Name) {
    if ($Name -eq "default") { return }
    $openUrl = Join-Path $PSScriptRoot "open-url.ps1"
    if (-not (Test-Path -LiteralPath $openUrl -PathType Leaf)) {
        throw "open-url.ps1 is missing"
    }
    $escapedScript = $openUrl.Replace('"', '\"')
    $escapedBrowser = $Name.Replace('"', '\"')
    $psi = [Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$escapedScript`" `"https://example.invalid`" -ForceBrowser `"$escapedBrowser`" -ResolveOnly"
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($psi)
    $process.WaitForExit(10000) | Out-Null
    if (-not $process.HasExited) {
        try { $process.Kill() } catch {}
        throw "Browser detection timed out: $Name"
    }
    if ($process.ExitCode -ne 0) {
        throw "Selected browser is not installed or its executable was not found: $Name"
    }
}

function Get-JarvisDbPath {
    $dir = Get-JarvisDataDir
    $db = Join-Path $dir "app.db"
    if (Test-Path -LiteralPath $db) { return $db }
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    return $db
}

function Acquire-SettingsLock([string]$Path) {
    $lockPath = [IO.Path]::ChangeExtension($Path, "db.lock")
    $deadline = [DateTime]::UtcNow.AddSeconds(5)
    while ($true) {
        try {
            return [IO.File]::Open(
                $lockPath,
                [IO.FileMode]::CreateNew,
                [IO.FileAccess]::Write,
                [IO.FileShare]::None
            )
        } catch [IO.IOException] {
            try {
                $item = Get-Item -LiteralPath $lockPath -ErrorAction Stop
                if ([DateTime]::UtcNow.Subtract($item.LastWriteTimeUtc).TotalSeconds -gt 10) {
                    Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
                    continue
                }
            } catch {}
            if ([DateTime]::UtcNow -ge $deadline) {
                throw "Timed out waiting for settings lock"
            }
            Start-Sleep -Milliseconds 20
        }
    }
}

Assert-BrowserAvailable $Browser.ToLowerInvariant()
$dbPath = Get-JarvisDbPath
$lock = Acquire-SettingsLock $dbPath
$lockPath = [IO.Path]::ChangeExtension($dbPath, "db.lock")
try {
    $db = $null
    if (Test-Path -LiteralPath $dbPath) {
        try {
            $raw = [IO.File]::ReadAllText($dbPath, [Text.Encoding]::UTF8)
            $db = $raw | ConvertFrom-Json
        } catch {
            throw "Cannot parse existing app.db; browser setting was not changed"
        }
    } else {
        $db = [pscustomobject]@{}
    }

    $db | Add-Member -NotePropertyName preferred_browser -NotePropertyValue $Browser.ToLowerInvariant() -Force
    $json = $db | ConvertTo-Json -Depth 20
    [IO.File]::WriteAllText($dbPath, $json, [Text.UTF8Encoding]::new($false))
}
finally {
    if ($lock) { $lock.Dispose() }
    Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
}
Write-Host "JARVIS preferred_browser=$Browser path=$dbPath"
exit 0
