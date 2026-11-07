# Start console tools (python.exe, powershell, cmd) without a visible window.
# A console host still flashes if it is created and then hidden. Spawn without a console instead.
# ASCII-only: Windows PowerShell 5.1.

function Get-JarvisHiddenArgString([string[]]$ArgumentList) {
    if (-not $ArgumentList -or $ArgumentList.Count -eq 0) { return "" }
    $parts = foreach ($raw in $ArgumentList) {
        $a = [string]$raw
        if ($a -eq "") { '""'; continue }
        # Callers sometimes pre-quote for Start-Process; strip so we do not double-quote
        # (python then sees a path like C:\cwd\"C:\real\speak.py" and dies).
        if ($a.Length -ge 2 -and $a.StartsWith('"') -and $a.EndsWith('"')) {
            $a = $a.Substring(1, $a.Length - 2)
        }
        if ($a -match '\s') {
            '"' + ($a -replace '"','\"') + '"'
        } else {
            $a
        }
    }
    return ($parts -join " ")
}

function Start-JarvisHiddenProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [string]$WorkingDirectory = "",
        [string]$RedirectStandardOutput = "",
        [string]$RedirectStandardError = "",
        [switch]$Wait
    )
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = Get-JarvisHiddenArgString $ArgumentList
    if ($WorkingDirectory -and (Test-Path -LiteralPath $WorkingDirectory)) {
        $psi.WorkingDirectory = $WorkingDirectory
    }
    $psi.UseShellExecute = $false
    # CreateNoWindow only — never use ProcessWindowStyle=Hide (Kaspersky / AV Trojan heuristic).
    $psi.CreateNoWindow = $true
    $needOut = -not [string]::IsNullOrWhiteSpace($RedirectStandardOutput)
    $needErr = -not [string]::IsNullOrWhiteSpace($RedirectStandardError)
    $psi.RedirectStandardOutput = $needOut
    $psi.RedirectStandardError = $needErr
    $p = [Diagnostics.Process]::Start($psi)
    if (-not $p) { return $null }
    if ($Wait) {
        $out = ""
        $err = ""
        if ($needOut -and $needErr) {
            $outTask = $p.StandardOutput.ReadToEndAsync()
            $errTask = $p.StandardError.ReadToEndAsync()
            [void][Threading.Tasks.Task]::WaitAll(@($outTask, $errTask))
            $out = $outTask.Result
            $err = $errTask.Result
        } elseif ($needOut) {
            $out = $p.StandardOutput.ReadToEnd()
        } elseif ($needErr) {
            $err = $p.StandardError.ReadToEnd()
        }
        $p.WaitForExit()
        if ($needOut) { [IO.File]::WriteAllText($RedirectStandardOutput, $out) }
        if ($needErr) { [IO.File]::WriteAllText($RedirectStandardError, $err) }
    }
    return $p
}

function Invoke-JarvisHiddenOutput {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [string]$WorkingDirectory = ""
    )
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = Get-JarvisHiddenArgString $ArgumentList
    if ($WorkingDirectory -and (Test-Path -LiteralPath $WorkingDirectory)) {
        $psi.WorkingDirectory = $WorkingDirectory
    }
    $psi.UseShellExecute = $false
    # CreateNoWindow only — never use ProcessWindowStyle=Hide (Kaspersky / AV Trojan heuristic).
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $p = [Diagnostics.Process]::Start($psi)
    if (-not $p) {
        return @{ ExitCode = -1; Output = "" }
    }
    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    $p.WaitForExit()
    return @{
        ExitCode = $p.ExitCode
        Output = [string]$stdout + [string]$stderr
    }
}
