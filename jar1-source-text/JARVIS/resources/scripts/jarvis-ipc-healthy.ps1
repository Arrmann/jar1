# Return 0 if JARVIS engine is running AND its LIVE process owns an IPC LISTEN port.
# Never treat a Windows ghost LISTEN (dead PID) as healthy.
param(
    [string]$ExpectedDir = ""
)

$ErrorActionPreference = "SilentlyContinue"

$engines = @(Get-Process -Name @("jarvis-app", "jarvis-run") -ErrorAction SilentlyContinue)
if (-not $engines -or $engines.Count -eq 0) { exit 1 }
$enginePids = @($engines | ForEach-Object { $_.Id })

if ($ExpectedDir) {
    $sameTree = Join-Path $PSScriptRoot "jarvis-same-tree.ps1"
    if (Test-Path -LiteralPath $sameTree) {
        & $sameTree -ExpectedDir $ExpectedDir -Check app
        if ($LASTEXITCODE -ne 0) { exit 1 }
    }
}

$ownedPorts = @()
# Prefer netstat first: Get-NetTCPConnection/NetTCPIP is missing or broken on many customer PCs.
$net = netstat -ano -p tcp 2>$null
foreach ($line in $net) {
    if ($line -notmatch 'LISTENING') { continue }
    $cols = $line -split '\s+' | Where-Object { $_ }
    if ($cols.Count -lt 5) { continue }
    $local = $cols[1]
    $ownerProcessId = 0
    [void][int]::TryParse($cols[-1], [ref]$ownerProcessId)
    if ($enginePids -notcontains $ownerProcessId) { continue }
    if ($local -match ':(\d+)$') {
        $p = [int]$Matches[1]
        if ($p -ge 9712 -and $p -le 9722) { $ownedPorts += $p }
    }
}
$ownedPorts = @($ownedPorts | Select-Object -Unique)

if ($ownedPorts.Count -eq 0) {
    Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
        Where-Object {
            $_.LocalPort -ge 9712 -and $_.LocalPort -le 9722 -and ($enginePids -contains $_.OwningProcess)
        } |
        ForEach-Object { $ownedPorts += [int]$_.LocalPort }
    $ownedPorts = @($ownedPorts | Select-Object -Unique)
}

if ($ownedPorts.Count -eq 0) { exit 1 }

foreach ($port in ($ownedPorts | Select-Object -Unique)) {
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $async = $client.BeginConnect("127.0.0.1", $port, $null, $null)
        if ($async.AsyncWaitHandle.WaitOne(400)) {
            $client.EndConnect($async)
            $client.Close()
            exit 0
        }
        $client.Close()
    } catch {}
}

exit 1
