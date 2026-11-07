# F12 while screen recording is active â†’ stop recording.
$ErrorActionPreference = "SilentlyContinue"
. (Join-Path $PSScriptRoot "_jarvis-data-dir.ps1")
$dataDir = Get-JarvisDataDir
$flag = Join-Path $dataDir "screen-record.active"
$watch = Join-Path $dataDir "screen-record.watch"
$stopScript = Join-Path $PSScriptRoot "screen-record.ps1"

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class JarvisScreenF12 {
  [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vKey);
  public const int VK_F12 = 0x7B;
}
"@ -ErrorAction SilentlyContinue

while ($true) {
    if (-not (Test-Path -LiteralPath $flag)) { break }
    if (-not (Test-Path -LiteralPath $watch)) { break }
    try {
        $state = [JarvisScreenF12]::GetAsyncKeyState(0x7B)
        if (($state -band 0x8000) -ne 0) {
            if (Test-Path -LiteralPath $stopScript) {
                Start-Process -FilePath "powershell" -ArgumentList @(
                    "-NoProfile", "-STA", "-ExecutionPolicy", "Bypass",
                    "-File", $stopScript, "-Action", "stop"
                ) -Wait | Out-Null
            }
            break
        }
    } catch {}
    Start-Sleep -Milliseconds 50
}
Remove-Item -LiteralPath $watch -Force -ErrorAction SilentlyContinue
exit 0
