# Shared JARVIS data directory resolver.
# JARVIS_CONFIG_DIR, else the pointer written by the app
# (%LOCALAPPDATA%\JARVIS\active-config-dir.txt), else %APPDATA%\com.jarvisn.assistant.
function Get-JarvisDataDir {
    $override = [string]$env:JARVIS_CONFIG_DIR
    if (-not [string]::IsNullOrWhiteSpace($override)) {
        return $override.TrimEnd('\', '/')
    }
    $local = [string]$env:LOCALAPPDATA
    if (-not [string]::IsNullOrWhiteSpace($local)) {
        $pointer = Join-Path $local "JARVIS\active-config-dir.txt"
        if (Test-Path -LiteralPath $pointer -PathType Leaf) {
            $line = (Get-Content -LiteralPath $pointer -TotalCount 1 -ErrorAction SilentlyContinue)
            $line = [string]$line
            if (-not [string]::IsNullOrWhiteSpace($line)) {
                $line = $line.Trim()
                if (Test-Path -LiteralPath $line -PathType Container) {
                    return $line
                }
            }
        }
    }
    $roaming = [string]$env:APPDATA
    if ([string]::IsNullOrWhiteSpace($roaming)) {
        $roaming = [Environment]::GetFolderPath('ApplicationData')
    }
    $current = Join-Path $roaming "com.jarvisn.assistant"
    if (Test-Path -LiteralPath $current -PathType Container) {
        return $current
    }
    # Pre-rename installs only — keep helpers working until first app migration.
    $legacy = Join-Path $roaming "com.priler.jarvis"
    if (Test-Path -LiteralPath $legacy -PathType Container) {
        return $legacy
    }
    return $current
}

# csc.exe / Add-Type: profile TEMP with Cyrillic fails; C:\Windows\Temp is not writable.
function Set-JarvisAsciiTemp {
    $candidates = @(
        "C:\ProgramData\JARVIS\pscache",
        "C:\Users\Public\JARVIS\pscache"
    )
    foreach ($dir in $candidates) {
        try {
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
            $probe = Join-Path $dir (".w-{0}" -f $PID)
            [IO.File]::WriteAllText($probe, "1")
            Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
            $env:TEMP = $dir
            $env:TMP = $dir
            return $dir
        } catch {}
    }
    return $env:TEMP
}
