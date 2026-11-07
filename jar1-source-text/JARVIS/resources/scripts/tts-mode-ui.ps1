# Clickable TTS mode settings for ordinary users (no CMD).
# Opens a dark teal panel matching JARVIS Settings.
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_jarvis-data-dir.ps1")
$setMode = Join-Path $PSScriptRoot "set-tts-mode.ps1"
$dataDir = Get-JarvisDataDir
$modeFile = Join-Path $dataDir "tts.mode"

function Get-Mode {
    if (Test-Path -LiteralPath $modeFile) {
        $m = (Get-Content -LiteralPath $modeFile -Raw).Trim().ToLowerInvariant()
        if ($m -eq "background") { return "background" }
    }
    try {
        $db = Join-Path $dataDir "app.db"
        if (Test-Path -LiteralPath $db) {
            $j = Get-Content -LiteralPath $db -Raw -Encoding UTF8 | ConvertFrom-Json
            if (("" + $j.tts_mode).ToLowerInvariant() -eq "background") { return "background" }
        }
    } catch {}
    return "ondemand"
}

function Apply-Mode([string]$Mode) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $setMode $Mode
    if ($LASTEXITCODE -ne 0) { throw "Не удалось сохранить режим" }
}

function Get-DaemonCount {
    $n = 0
    Get-CimInstance Win32_Process -Filter "Name = 'python.exe'" -ErrorAction SilentlyContinue | ForEach-Object {
        $cmd = [string]$_.CommandLine
        if ($cmd -and (($cmd -like "*tts_daemon.py*") -or ($cmd -like "*\resources\tts\*speak*"))) {
            $n++
        }
    }
    return $n
}

$script:current = Get-Mode

$form = New-Object System.Windows.Forms.Form
$form.Text = "JARVIS — Режим озвучки"
$form.Size = New-Object System.Drawing.Size(500, 420)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.TopMost = $true
$form.BackColor = [System.Drawing.Color]::FromArgb(14, 24, 32)
$form.ForeColor = [System.Drawing.Color]::White
$form.Font = New-Object System.Drawing.Font("Segoe UI", 10)

$title = New-Object System.Windows.Forms.Label
$title.Text = "Режим озвучки текста (Silero)"
$title.Location = New-Object System.Drawing.Point(24, 20)
$title.AutoSize = $true
$title.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 14)

$desc = New-Object System.Windows.Forms.Label
$desc.Text = "Это не голос Миты. Это «прочитай / озвучь»." + [Environment]::NewLine +
             "Фоновый = модель всегда в памяти (быстрее, но греет ПК)." + [Environment]::NewLine +
             "Только во время = загружается на чтение и выгружается (прохладнее)."
$desc.Location = New-Object System.Drawing.Point(24, 54)
$desc.Size = New-Object System.Drawing.Size(440, 70)
$desc.ForeColor = [System.Drawing.Color]::FromArgb(180, 200, 210)

$status = New-Object System.Windows.Forms.Label
$status.Location = New-Object System.Drawing.Point(24, 300)
$status.Size = New-Object System.Drawing.Size(440, 48)
$status.ForeColor = [System.Drawing.Color]::FromArgb(92, 246, 240)

$hint = New-Object System.Windows.Forms.Label
$hint.Text = "Голосом: «джарвис, режим озвучки» · или ярлык «Режим озвучки»"
$hint.Location = New-Object System.Drawing.Point(24, 350)
$hint.Size = New-Object System.Drawing.Size(440, 28)
$hint.ForeColor = [System.Drawing.Color]::FromArgb(120, 140, 150)
$hint.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)

function Style-Button($btn, [bool]$selected) {
    $btn.FlatStyle = "Flat"
    $btn.FlatAppearance.BorderSize = 2
    $btn.Size = New-Object System.Drawing.Size(210, 120)
    $btn.TextAlign = "MiddleLeft"
    $btn.Padding = New-Object System.Windows.Forms.Padding(14, 10, 14, 10)
    $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btn.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
    if ($selected) {
        $btn.BackColor = [System.Drawing.Color]::FromArgb(22, 48, 52)
        $btn.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(92, 246, 240)
        $btn.ForeColor = [System.Drawing.Color]::White
    } else {
        $btn.BackColor = [System.Drawing.Color]::FromArgb(20, 32, 40)
        $btn.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(70, 90, 100)
        $btn.ForeColor = [System.Drawing.Color]::FromArgb(230, 240, 245)
    }
}

function Update-Status {
    $daemons = Get-DaemonCount
    if ($script:current -eq "background") {
        $status.Text = "Сейчас: ФОНОВЫЙ · процессов Silero: $daemons" + [Environment]::NewLine + "ПК может греться — модель в памяти."
    } else {
        $status.Text = "Сейчас: ТОЛЬКО ВО ВРЕМЯ ОЗВУЧКИ · процессов Silero: $daemons" + [Environment]::NewLine + "После чтения модель выгружается."
    }
    Style-Button $btnOn $false
    Style-Button $btnBg $false
    if ($script:current -eq "background") { Style-Button $btnBg $true } else { Style-Button $btnOn $true }
}

$btnOn = New-Object System.Windows.Forms.Button
$btnOn.Text = "Только во время" + [Environment]::NewLine + "озвучки" + [Environment]::NewLine + [Environment]::NewLine + "Не греет ПК"
$btnOn.Location = New-Object System.Drawing.Point(24, 140)

$btnBg = New-Object System.Windows.Forms.Button
$btnBg.Text = "Фоновый" + [Environment]::NewLine + "(быстрый старт)" + [Environment]::NewLine + [Environment]::NewLine + "Может греть ПК"
$btnBg.Location = New-Object System.Drawing.Point(250, 140)

$btnOn.Add_Click({
    try {
        $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
        Apply-Mode "ondemand"
        $script:current = "ondemand"
        Update-Status
    } catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "JARVIS", "OK", "Error") | Out-Null
    } finally {
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
    }
})

$btnBg.Add_Click({
    try {
        $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
        Apply-Mode "background"
        $script:current = "background"
        Update-Status
    } catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "JARVIS", "OK", "Error") | Out-Null
    } finally {
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
    }
})

Update-Status
$form.Controls.AddRange(@($title, $desc, $btnOn, $btnBg, $status, $hint))
[void]$form.ShowDialog()
