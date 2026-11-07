# Shared HTTP download for JARVIS (Windows PowerShell 5.1).
# TLS 1.2, curl.exe with retries/resume, atomic .part rename, size check.
# Dot-source from other scripts. ASCII-only.

if (-not $script:JarvisDownloadInit) {
    $script:JarvisDownloadInit = $true
    try {
        [Net.ServicePointManager]::SecurityProtocol =
            [Net.SecurityProtocolType]::Tls12 -bor
            [Net.SecurityProtocolType]::Tls11 -bor
            [Net.SecurityProtocolType]::Tls
    } catch {
        try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
    }
    $ProgressPreference = "SilentlyContinue"
}

function Invoke-JarvisDownload {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,
        [Parameter(Mandatory = $true)]
        [string]$OutPath,
        [long]$MinBytes = 1024,
        [int]$Retries = 6,
        [int]$MaxTimeSec = 3600
    )

    $parent = Split-Path -Parent $OutPath
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    if (Test-Path -LiteralPath $OutPath) {
        try {
            if ((Get-Item -LiteralPath $OutPath).Length -ge $MinBytes) {
                return
            }
        } catch {}
        Remove-Item -LiteralPath $OutPath -Force -ErrorAction SilentlyContinue
    }

    $tmp = "$OutPath.part"
    $last = $null
    $curl = $null
    try { $curl = Get-Command curl.exe -CommandType Application -ErrorAction Stop } catch {}

    for ($i = 1; $i -le $Retries; $i++) {
        try {
            $resume = $false
            if ((Test-Path -LiteralPath $tmp) -and ((Get-Item -LiteralPath $tmp).Length -gt 0)) {
                $resume = $true
            } else {
                Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
            }

            if ($curl) {
                $curlArgs = @(
                    "-L", "--fail", "--retry", "3", "--retry-delay", "3",
                    "--connect-timeout", "30", "--max-time", "$MaxTimeSec",
                    "-A", "JARVIS/1.0",
                    "-o", $tmp
                )
                if ($resume) { $curlArgs = @("-C", "-") + $curlArgs }
                & curl.exe @curlArgs $Url
                if ($LASTEXITCODE -ne 0) { throw "curl exit $LASTEXITCODE for $Url" }
            } else {
                Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
                $wc = New-Object System.Net.WebClient
                $wc.Headers.Add("User-Agent", "JARVIS/1.0")
                try {
                    $wc.DownloadFile($Url, $tmp)
                } finally {
                    $wc.Dispose()
                }
            }
            if (-not (Test-Path -LiteralPath $tmp)) { throw "no file written" }
            $got = (Get-Item -LiteralPath $tmp).Length
            if ($got -lt $MinBytes) { throw "too small ($got bytes, need $MinBytes)" }
            Move-Item -LiteralPath $tmp -Destination $OutPath -Force
            return
        } catch {
            $last = $_
            # Keep .part for resume on next try unless tiny garbage
            try {
                if ((Test-Path -LiteralPath $tmp) -and ((Get-Item -LiteralPath $tmp).Length -lt 4096)) {
                    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
                }
            } catch {}
            if ($i -lt $Retries) { Start-Sleep -Seconds ([Math]::Min(20, 3 * $i)) }
        }
    }
    throw "Download failed after $Retries tries: $Url ($last)"
}

function Invoke-JarvisDownloadAny {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Urls,
        [Parameter(Mandatory = $true)]
        [string]$OutPath,
        [long]$MinBytes = 1024,
        [int]$RetriesPerUrl = 3,
        [int]$MaxTimeSec = 3600
    )
    $errors = @()
    foreach ($u in $Urls) {
        if ([string]::IsNullOrWhiteSpace($u)) { continue }
        try {
            Write-Host "  TRY $u"
            Invoke-JarvisDownload -Url $u.Trim() -OutPath $OutPath -MinBytes $MinBytes -Retries $RetriesPerUrl -MaxTimeSec $MaxTimeSec
            return
        } catch {
            $errors += [string]$_
            Write-Host ("  FAIL: " + $_)
        }
    }
    throw ("All mirrors failed for $OutPath : " + ($errors -join " | "))
}
