param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet("mute", "unmute", "toggle")]
    [string]$Action
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "audio-core.ps1")

try {
    switch ($Action.ToLowerInvariant()) {
        "mute" { [JarvisCoreAudio.Volume]::SetMuted($true) }
        "unmute" {
            if ([JarvisCoreAudio.Volume]::GetMuted()) {
                [JarvisCoreAudio.Volume]::SetMuted($false)
            }
        }
        "toggle" {
            $cur = [JarvisCoreAudio.Volume]::GetMuted()
            [JarvisCoreAudio.Volume]::SetMuted(-not $cur)
        }
    }
    Write-Host "JARVIS mute action=$Action"
    exit 0
} catch {
    Write-Warning "Core Audio mute unavailable ($($_.Exception.Message)); using key toggle"
    # unmute via toggle only if we can; key is toggle-only
    [JarvisCoreAudio.Volume]::MuteByKey()
    Write-Host "JARVIS mute key-fallback action=$Action"
    exit 0
}
