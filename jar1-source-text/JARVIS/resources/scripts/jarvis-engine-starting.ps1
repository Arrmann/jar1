# Exit 0 only while this session's engine owns its startup/lifetime mutex.
# Read-only probe: never terminates a process or modifies IPC files.
param([string]$MutexName = 'Local\JARVIS.VoiceEngine.v1')
$ErrorActionPreference = 'Stop'
try {
    $mutex = [Threading.Mutex]::OpenExisting($MutexName)
    try {
        try { $acquired = $mutex.WaitOne(0) }
        catch [Threading.AbandonedMutexException] { $acquired = $true }
        if (-not $acquired) { exit 0 }
        $mutex.ReleaseMutex()
    } finally { $mutex.Dispose() }
} catch {}
exit 1
