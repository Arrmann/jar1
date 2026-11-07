param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet("up", "down")]
    [string]$Direction,

    # ~2% per media-key step; 8 steps ≈ 16% — noticeable "громче/тише"
    [Parameter(Mandatory = $false, Position = 1)]
    [int]$Steps = 8
)

$ErrorActionPreference = "Stop"
if ($Steps -lt 1) { $Steps = 1 }
if ($Steps -gt 25) { $Steps = 25 }

. (Join-Path $PSScriptRoot "audio-core.ps1")

# Media keys are more reliable for relative nudge than SendKeys/WScript.
# Absolute set-volume.ps1 still uses Core Audio SetScalar.
$vk = if ($Direction -eq "up") {
    [JarvisCoreAudio.NativeKeys]::VK_VOLUME_UP
} else {
    [JarvisCoreAudio.NativeKeys]::VK_VOLUME_DOWN
}

# Raising volume should unmute.
if ($Direction -eq "up") {
    try {
        if ([JarvisCoreAudio.Volume]::GetMuted()) {
            [JarvisCoreAudio.Volume]::SetMuted($false)
        }
    } catch {}
}

for ($i = 0; $i -lt $Steps; $i++) {
    [JarvisCoreAudio.NativeKeys]::Tap($vk)
    Start-Sleep -Milliseconds 30
}
Write-Host "JARVIS volume nudge $Direction steps=$Steps"
exit 0
