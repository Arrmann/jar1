# Watches Esc while native dictation is active — full session stop (not just the flag).
$ErrorActionPreference = "SilentlyContinue"
. (Join-Path $PSScriptRoot "_jarvis-data-dir.ps1")
$dataDir = Get-JarvisDataDir
$flag = Join-Path $dataDir "dictate.active"
$ignoreFile = Join-Path $dataDir "dictate.ignore_until"
$deadlineFile = Join-Path $dataDir "dictate.deadline"
$watchPidFile = Join-Path $dataDir "dictate.watch.pid"
$stoppedFile = Join-Path $dataDir "dictate.stopped"

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class JarvisDictateEsc {
  [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vKey);
  public const int VK_ESCAPE = 0x1B;
}
"@ -ErrorAction SilentlyContinue

while ($true) {
    if (-not (Test-Path -LiteralPath $flag)) { break }
    try {
        $state = [JarvisDictateEsc]::GetAsyncKeyState(0x1B)
        # 0x8000 = held now; 1 = pressed since last poll
        if (($state -band 0x8000) -ne 0 -or ($state -band 1) -ne 0) {
            foreach ($f in @($flag, $ignoreFile, $deadlineFile, $watchPidFile)) {
                Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
            }
            Set-Content -LiteralPath $stoppedFile -Value "1" -Encoding ASCII -ErrorAction SilentlyContinue
            break
        }
    } catch {}
    Start-Sleep -Milliseconds 40
}
exit 0
