param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet("up", "down", "page_up", "page_down", "top", "bottom", "left", "right")]
    [string]$Action
)

$ErrorActionPreference = "Stop"
$w = New-Object -ComObject WScript.Shell
Start-Sleep -Milliseconds 60

switch ($Action) {
    "up" { 1..3 | ForEach-Object { $w.SendKeys("{UP}") } }
    "down" { 1..3 | ForEach-Object { $w.SendKeys("{DOWN}") } }
    "page_up" { $w.SendKeys("{PGUP}") }
    "page_down" { $w.SendKeys("{PGDN}") }
    "top" { $w.SendKeys("^{HOME}") }
    "bottom" { $w.SendKeys("^{END}") }
    "left" { 1..3 | ForEach-Object { $w.SendKeys("{LEFT}") } }
    "right" { 1..3 | ForEach-Object { $w.SendKeys("{RIGHT}") } }
}

exit 0
