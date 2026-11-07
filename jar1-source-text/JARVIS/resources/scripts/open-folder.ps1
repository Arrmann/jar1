param(
    [Parameter(Mandatory = $false, Position = 0)]
    [string]$Path = "",

    # Well-known folders so Lua does not invent paths.
    [Parameter(Mandatory = $false)]
    [ValidateSet("", "screenshots", "downloads", "documents", "desktop", "home")]
    [string]$Known = "",

    [Parameter(Mandatory = $false)]
    [string[]]$TitleHints = @(),

    [switch]$EnsureDirectory
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_jarvis-last-target.ps1")
Initialize-JarvisLastTarget
Invoke-JarvisPrepareOpen

# ASCII-only hints in source (Windows Explorer titles may still be localized at runtime).
switch ($Known.ToLowerInvariant()) {
    "screenshots" {
        $Path = Join-Path ([Environment]::GetFolderPath("MyPictures")) "JARVIS Screenshots"
        $EnsureDirectory = $true
        if ($TitleHints.Count -lt 1) { $TitleHints = @("JARVIS Screenshots", "Screenshots") }
    }
    "downloads" {
        $Path = Join-Path ([Environment]::GetFolderPath("UserProfile")) "Downloads"
        if ($TitleHints.Count -lt 1) { $TitleHints = @("Downloads") }
    }
    "documents" {
        $Path = [Environment]::GetFolderPath("MyDocuments")
        if ($TitleHints.Count -lt 1) { $TitleHints = @("Documents") }
    }
    "desktop" {
        $Path = [Environment]::GetFolderPath("Desktop")
        if ($TitleHints.Count -lt 1) { $TitleHints = @("Desktop") }
    }
    "home" {
        $Path = "shell:MyComputerFolder"
        if ($TitleHints.Count -lt 1) { $TitleHints = @("This PC", "File Explorer") }
    }
}

$isShell = ($Path -like "shell:*")
if (-not $isShell) {
    $path = [Environment]::ExpandEnvironmentVariables("$Path").Trim().Trim('"')
    if ([string]::IsNullOrWhiteSpace($path)) {
        throw "Empty folder path"
    }
    if ($EnsureDirectory -and -not (Test-Path -LiteralPath $path)) {
        New-Item -ItemType Directory -Force -Path $path | Out-Null
    }
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Folder not found: $path"
    }
    Start-Process -FilePath "explorer.exe" -ArgumentList ("`"{0}`"" -f $path) -ErrorAction Stop | Out-Null
    Register-JarvisOpenedFolder -Path $path -TitleHints $TitleHints
} else {
    Start-Process -FilePath "explorer.exe" -ArgumentList $Path -ErrorAction Stop | Out-Null
    Initialize-JarvisLastTarget
    Invoke-JarvisPrepareOpen
    Save-JarvisLastTarget -Hwnd ([IntPtr]::Zero) -Process "explorer" -Title "Explorer" -Url $Path -Keywords $TitleHints -Kind "explorer"
    $hit = [JarvisLastTarget]::FindExplorerByKeywords([string[]]$TitleHints, $true)
    if ($hit -eq [IntPtr]::Zero) { $hit = [JarvisLastTarget]::FindTopExplorerFolder($true) }
    if ($hit -ne [IntPtr]::Zero) {
        $title = [JarvisLastTarget]::TitleOf($hit)
        Save-JarvisLastTarget -Hwnd $hit -Process "explorer" -Title $title -Url $Path -Keywords $TitleHints -Kind "explorer"
        [void][JarvisLastTarget]::FocusWindow($hit)
    }
    for ($i = 0; $i -lt 12; $i++) {
        if ($i -gt 0) { Start-Sleep -Milliseconds 50 }
        $hit = [JarvisLastTarget]::FindExplorerByKeywords([string[]]$TitleHints, $true)
        if ($hit -eq [IntPtr]::Zero) { $hit = [JarvisLastTarget]::FindTopExplorerFolder($true) }
        if ($hit -ne [IntPtr]::Zero) {
            $title = [JarvisLastTarget]::TitleOf($hit)
            Save-JarvisLastTarget -Hwnd $hit -Process "explorer" -Title $title -Url $Path -Keywords $TitleHints -Kind "explorer"
            [void][JarvisLastTarget]::FocusWindow($hit)
            [void][JarvisLastTarget]::WaitForegroundExact($hit, 8)
            break
        }
    }
    $path = $Path
}
Write-Host "JARVIS open-folder: $path"
exit 0
