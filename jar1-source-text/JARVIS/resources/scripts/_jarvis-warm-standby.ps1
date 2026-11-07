# Warm PowerShell standby for JARVIS. Jobs are a script file plus arguments.
$ErrorActionPreference = 'Continue'
$pre = $env:JARVIS_WARM_PRELOAD
Remove-Item Env:JARVIS_WARM_PRELOAD -ErrorAction SilentlyContinue
try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
    '{"a":1}' | ConvertFrom-Json | ConvertTo-Json -Compress | Out-Null
    if ($pre -and (Test-Path -LiteralPath $pre)) { & { . $pre; Initialize-JarvisLastTarget } }
} catch {}
$line = [Console]::In.ReadLine()
if ([string]::IsNullOrWhiteSpace($line)) { exit 0 }
$job = $line | ConvertFrom-Json
Set-Location -LiteralPath $job.cwd
[Environment]::CurrentDirectory = $job.cwd
$argText = foreach ($a in @($job.args)) {
    if ($a -cmatch '^-[A-Za-z_][\w-]*$') { $a } else { "'" + ($a -replace "'", "''") + "'" }
}
$global:LASTEXITCODE = 0
try {
    & ([scriptblock]::Create("& '" + ($job.script -replace "'", "''") + "' " + ($argText -join ' ')))
} catch {
    exit 1
}
exit $LASTEXITCODE
