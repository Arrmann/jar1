# Install / repair Microsoft Edge WebView2 Runtime using the bundled bootstrapper.
param(
    [Parameter(Mandatory = $true)]
    [string]$AppDir
)

$ErrorActionPreference = "Stop"
$AppDir = [IO.Path]::GetFullPath($AppDir)

function Test-WebView2Installed {
    $keys = @(
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}",
        "HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}",
        "HKCU:\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}"
    )
    foreach ($k in $keys) {
        try {
            $pv = (Get-ItemProperty -LiteralPath $k -ErrorAction Stop).pv
            if ($pv) { return $true }
        } catch {}
    }
    return $false
}

if (Test-WebView2Installed) {
    Write-Host "WebView2 already installed."
    exit 0
}

$boot = Join-Path $AppDir "MicrosoftEdgeWebView2Setup.exe"
if (-not (Test-Path -LiteralPath $boot)) {
    Write-Error "MicrosoftEdgeWebView2Setup.exe missing in $AppDir"
    exit 2
}

Write-Host "Installing WebView2 Runtime (needs internet once)..."
$p = Start-Process -FilePath $boot -ArgumentList @("/silent", "/install") -Wait -PassThru
if (Test-WebView2Installed) {
    Write-Host "WebView2 installed OK (exit $($p.ExitCode))."
    exit 0
}

Write-Error "WebView2 still missing after bootstrapper (exit $($p.ExitCode)). Check internet / antivirus."
exit 1
