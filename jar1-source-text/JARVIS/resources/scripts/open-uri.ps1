param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Uri
)

$ErrorActionPreference = "Stop"
$Uri = $Uri.Trim().Trim('"')
if ([string]::IsNullOrWhiteSpace($Uri)) {
    Write-Error "URI is empty"
    exit 1
}

# Never use `cmd /c start` here: with CREATE_NO_WINDOW it often opens Explorer
# on the app working directory instead of the ms-settings:/protocol URI.
try {
    Start-Process -FilePath $Uri -ErrorAction Stop | Out-Null
    Write-Host "JARVIS open-uri: $Uri"
    exit 0
} catch {
    try {
        Start-Process -FilePath "explorer.exe" -ArgumentList $Uri -ErrorAction Stop | Out-Null
        Write-Host "JARVIS open-uri via explorer: $Uri"
        exit 0
    } catch {
        Write-Error "Failed to open URI '$Uri': $($_.Exception.Message)"
        exit 1
    }
}
