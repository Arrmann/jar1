param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Kind,

    [Parameter(Mandatory = $true, Position = 1)]
    [AllowEmptyString()]
    [string]$Target
)

$ErrorActionPreference = "Stop"
$Target = $Target.Trim().Trim('"')
$Kind = $Kind.Trim().ToLowerInvariant()
. (Join-Path $PSScriptRoot "_jarvis-hidden-process.ps1")

# When called via `& script.ps1` from a parent runner, never `exit` the host process.
function Jarvis-Finish([int]$Code = 0) {
    Set-Variable -Name JARVIS_LAST_EXIT -Scope Global -Value $Code
    if ($env:JARVIS_PS_NESTED -ne '1') {
        exit $Code
    }
}

# Keys step: classic WScript SendKeys for Ctrl/Alt/Shift.
# Win is NOT supported by SendKeys - use # / {WIN} / win+... and native Chord (keybd_event).
# Examples: #^v = Win+Ctrl+V, #v = Win+V, win+ctrl+v (human form), #{LEFT} = Win+Left.

function ConvertTo-JarvisKeysSpec([string]$keys) {
    $s = ($keys -as [string]).Trim()
    if ([string]::IsNullOrWhiteSpace($s)) { return $s }

    # Human form: win+ctrl+v / windows+alt+f4 / "win + ctrl + v" (spaces ok)
    if ($s -match '(?i)^(win(?:dows)?|lwin|rwin)\s*[\+-]') {
        $s = $s -replace '\s+', ''
    }

    if ($s -match '(?i)^(win(?:dows)?|lwin|rwin)(?:\+|-)(.+)$') {
        $rest = $Matches[2]
        $parts = @($rest -split '\+' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $out = '#'
        foreach ($p in $parts) {
            $pl = $p.ToLowerInvariant()
            switch ($pl) {
                { $_ -in @('ctrl', 'control', 'ctl') } { $out += '^'; continue }
                { $_ -in @('alt', 'menu', 'opt') } { $out += '%'; continue }
                { $_ -in @('shift', 'shft') } { $out += '+'; continue }
                { $_ -in @('win', 'windows', 'lwin', 'rwin') } { continue }
                default {
                    if ($p -match '^[a-zA-Z0-9]$') {
                        $out += $p.ToLowerInvariant()
                    } elseif ($p -match '^\{.+\}$') {
                        $out += $p.ToUpperInvariant()
                    } else {
                        $out += '{' + $p.ToUpperInvariant() + '}'
                    }
                }
            }
        }
        return $out
    }

    # {WIN}+ctrl+v style
    if ($s -match '(?i)^\{WIN\}\s*(?:\+|-)\s*(.+)$') {
        return (ConvertTo-JarvisKeysSpec ("win+" + ($Matches[1] -replace '\s+', '')))
    }

    return $s
}

function Test-JarvisKeysNeedWin([string]$keys) {
    if ([string]::IsNullOrWhiteSpace($keys)) { return $false }
    if ($keys.Contains('#')) { return $true }
    if ($keys -match '(?i)\{WIN\}') { return $true }
    if ($keys -match '(?i)^(win(?:dows)?|lwin|rwin)\s*(\+|-)') { return $true }
    return $false
}

function Get-JarvisVkFromToken([string]$token) {
    $t = $token.Trim()
    if ([string]::IsNullOrEmpty($t)) { return $null }
    if ($t.StartsWith('{') -and $t.EndsWith('}')) {
        $name = $t.Substring(1, $t.Length - 2).Trim().ToUpperInvariant()
    } else {
        $name = $t.ToUpperInvariant()
    }

    switch ($name) {
        { $_ -in @('WIN', 'LWIN', 'RWIN', 'WINDOWS') } { return [byte]0x5B }
        { $_ -in @('CTRL', 'CONTROL', 'CTL') } { return [byte]0x11 }
        { $_ -in @('ALT', 'MENU') } { return [byte]0x12 }
        { $_ -in @('SHIFT') } { return [byte]0x10 }
        { $_ -in @('ENTER', 'RETURN') } { return [byte]0x0D }
        { $_ -in @('ESC', 'ESCAPE') } { return [byte]0x1B }
        { $_ -in @('TAB') } { return [byte]0x09 }
        { $_ -in @('SPACE', 'SPC') } { return [byte]0x20 }
        { $_ -in @('BS', 'BKSP', 'BACKSPACE') } { return [byte]0x08 }
        { $_ -in @('DEL', 'DELETE') } { return [byte]0x2E }
        { $_ -in @('INS', 'INSERT') } { return [byte]0x2D }
        { $_ -in @('HOME') } { return [byte]0x24 }
        { $_ -in @('END') } { return [byte]0x23 }
        { $_ -in @('PGUP', 'PG UP', 'PRIOR') } { return [byte]0x21 }
        { $_ -in @('PGDN', 'PG DN', 'NEXT') } { return [byte]0x22 }
        { $_ -in @('LEFT') } { return [byte]0x25 }
        { $_ -in @('UP') } { return [byte]0x26 }
        { $_ -in @('RIGHT') } { return [byte]0x27 }
        { $_ -in @('DOWN') } { return [byte]0x28 }
        { $_ -in @('PRTSC', 'PRINTSCREEN', 'SNAPSHOT') } { return [byte]0x2C }
        default {
            if ($name -match '^F([1-9]|1[0-2])$') {
                return [byte](0x70 + [int]$Matches[1] - 1)
            }
            if ($name.Length -eq 1) {
                $ch = $name[0]
                if ($ch -ge 'A' -and $ch -le 'Z') { return [byte][int][char]$ch }
                if ($ch -ge '0' -and $ch -le '9') { return [byte][int][char]$ch }
            }
            return $null
        }
    }
}

function ConvertTo-JarvisVkChord([string]$keys) {
    $s = ConvertTo-JarvisKeysSpec $keys
    $list = New-Object System.Collections.Generic.List[byte]
    $i = 0
    $len = $s.Length

    while ($i -lt $len) {
        $c = $s[$i]
        if ($c -eq '#') {
            $list.Add([byte]0x5B) # VK_LWIN
            $i++
            continue
        }
        if ($c -eq '^') {
            $list.Add([byte]0x11) # VK_CONTROL
            $i++
            continue
        }
        if ($c -eq '%') {
            $list.Add([byte]0x12) # VK_MENU (Alt)
            $i++
            continue
        }
        if ($c -eq '+') {
            $list.Add([byte]0x10) # VK_SHIFT
            $i++
            continue
        }
        if ($c -eq '{') {
            $end = $s.IndexOf('}', $i)
            if ($end -lt 0) { throw "Unclosed key token in: $keys" }
            $token = $s.Substring($i, $end - $i + 1)
            $vk = Get-JarvisVkFromToken $token
            if ($null -eq $vk) { throw "Unknown key token: $token" }
            $list.Add([byte]$vk)
            $i = $end + 1
            # One chord per keys step when Win is involved (mods + one main key).
            break
        }

        # Single character key (letter/digit/punctuation as VK when A-Z/0-9)
        $token = [string]$c
        $vk = Get-JarvisVkFromToken $token
        if ($null -eq $vk) { throw "Unsupported key char '$c' in: $keys (use {ENTER} style for specials)" }
        $list.Add([byte]$vk)
        $i++
        break
    }

    if ($list.Count -eq 0) { throw "Empty key chord: $keys" }
    return ,$list.ToArray()
}

function Send-KeysSequence([string]$keys) {
    $raw = ($keys -as [string]).Trim()
    if ([string]::IsNullOrWhiteSpace($raw)) { throw "Empty keys sequence" }

    # WScript.SendKeys rejects {SPACE} ("Value does not fall within the expected range").
    # Route lone braced specials + Win chords through native VK Chord.
    $preferNative = (Test-JarvisKeysNeedWin $raw) -or (
        $raw -match '(?i)^\{(SPACE|SPC|ENTER|RETURN|ESC|ESCAPE|TAB|BS|BKSP|BACKSPACE|DEL|DELETE|HOME|END|LEFT|RIGHT|UP|DOWN|PGUP|PGDN|F([1-9]|1[0-2]))\}$'
    )

    if ($preferNative) {
        $norm = if (Test-JarvisKeysNeedWin $raw) { ConvertTo-JarvisKeysSpec $raw } else { $raw }
        $vks = ConvertTo-JarvisVkChord $norm
        if ($env:JARVIS_KEYS_DRY_RUN -eq '1') {
            $hex = ($vks | ForEach-Object { ('0x{0:X2}' -f $_) }) -join ','
            Write-Host ("JARVIS keys dry-run: '{0}' -> '{1}' -> [{2}]" -f $raw, $norm, $hex)
            return
        }
        . (Join-Path $PSScriptRoot "_jarvis-last-target.ps1")
        Initialize-JarvisLastTarget
        Start-Sleep -Milliseconds 40
        # Same Chord path as browser-control / Win+Up - works across Win10/11 layouts.
        # Force [byte[]] so a single-key chord is not unwrapped by PowerShell.
        [JarvisLastTarget]::Chord([byte[]]$vks)
        return
    }

    # SendKeys: map {SPACE} to literal space if it slipped through mixed sequences.
    $send = $raw -replace '(?i)\{SPACE\}|\{SPC\}', ' '

    if ($env:JARVIS_KEYS_DRY_RUN -eq '1') {
        Write-Host ("JARVIS keys dry-run SendKeys: '{0}'" -f $send)
        return
    }

    $w = New-Object -ComObject WScript.Shell
    Start-Sleep -Milliseconds 40
    $w.SendKeys($send)
}

function Set-ClipboardText([string]$text) {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.Clipboard]::SetText($text)
}

function Type-Text([string]$text) {
    if ([string]::IsNullOrEmpty($text)) { return }
    Set-ClipboardText $text
    Start-Sleep -Milliseconds 40
    Send-KeysSequence "^v"
}

function Start-JarvisTarget([string]$path) {
    $ext = [IO.Path]::GetExtension($path).ToLowerInvariant()
    $workDir = $null
    try {
        $parent = [IO.Path]::GetDirectoryName($path)
        if (-not [string]::IsNullOrWhiteSpace($parent) -and (Test-Path -LiteralPath $parent)) {
            $workDir = $parent
        }
    } catch {}
    if ($ext -eq ".cmd" -or $ext -eq ".bat") {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "$env:SystemRoot\System32\cmd.exe"
        $psi.Arguments = "/D /C `"`"$path`"`""
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        if ($workDir) { $psi.WorkingDirectory = $workDir }
        [void][System.Diagnostics.Process]::Start($psi)
        return
    }
    if ($workDir) {
        Start-Process -FilePath $path -WorkingDirectory $workDir | Out-Null
    } else {
        Start-Process -FilePath $path | Out-Null
    }
}

function Invoke-Mouse([string]$spec) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class JarvisMouse {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT lpPoint);
  public struct POINT { public int X; public int Y; }
  public const uint LEFTDOWN = 0x0002;
  public const uint LEFTUP = 0x0004;
  public const uint RIGHTDOWN = 0x0008;
  public const uint RIGHTUP = 0x0010;
}
"@ -ErrorAction SilentlyContinue

    $s = $spec.Trim().ToLowerInvariant()
    switch -Regex ($s) {
        '^(click_left|lclick|left)$' {
            [JarvisMouse]::mouse_event([JarvisMouse]::LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
            [JarvisMouse]::mouse_event([JarvisMouse]::LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
            return
        }
        '^(click_right|rclick|right)$' {
            [JarvisMouse]::mouse_event([JarvisMouse]::RIGHTDOWN, 0, 0, 0, [UIntPtr]::Zero)
            [JarvisMouse]::mouse_event([JarvisMouse]::RIGHTUP, 0, 0, 0, [UIntPtr]::Zero)
            return
        }
        '^(dblclick|double_click|double)$' {
            [JarvisMouse]::mouse_event([JarvisMouse]::LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
            [JarvisMouse]::mouse_event([JarvisMouse]::LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
            Start-Sleep -Milliseconds 40
            [JarvisMouse]::mouse_event([JarvisMouse]::LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
            [JarvisMouse]::mouse_event([JarvisMouse]::LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
            return
        }
        '^move:(-?\d+),(-?\d+)$' {
            $pt = New-Object JarvisMouse+POINT
            [void][JarvisMouse]::GetCursorPos([ref]$pt)
            $nx = $pt.X + [int]$Matches[1]
            $ny = $pt.Y + [int]$Matches[2]
            [void][JarvisMouse]::SetCursorPos($nx, $ny)
            return
        }
        '^move_to:(\d+),(\d+)$' {
            [void][JarvisMouse]::SetCursorPos([int]$Matches[1], [int]$Matches[2])
            return
        }
        default {
            throw "Unknown mouse action: $spec (use click_left, click_right, dblclick, move:dx,dy, move_to:x,y)"
        }
    }
}

function Invoke-Search([string]$spec) {
    $engine = "google"
    $query = $spec
    if ($spec -match '^(google|youtube|wiki|wikipedia|browser|yandex|images)\s*:\s*(.+)$') {
        $engine = $Matches[1].ToLowerInvariant()
        $query = $Matches[2]
    }
    $q = [Uri]::EscapeDataString($query)
    $url = switch ($engine) {
        "youtube" { "https://www.youtube.com/results?search_query=$q" }
        "wiki" { "https://ru.wikipedia.org/wiki/Special:Search?search=$q" }
        "wikipedia" { "https://ru.wikipedia.org/wiki/Special:Search?search=$q" }
        "yandex" { "https://yandex.ru/search/?text=$q" }
        "images" { "https://www.google.com/search?tbm=isch&q=$q" }
        "browser" { "https://www.google.com/search?q=$q" }
        default { "https://www.google.com/search?q=$q" }
    }
    $openUrl = Join-Path $PSScriptRoot "open-url.ps1"
    $prevNested = $env:JARVIS_PS_NESTED
    $env:JARVIS_PS_NESTED = '1'
    $global:JARVIS_LAST_EXIT = 0
        try { & $openUrl $url } catch {
            if ("$($_.Exception.Message)" -notlike 'JARVIS_OPEN_URL_DONE:*') { throw }
        } finally {
            if ([string]::IsNullOrEmpty($prevNested)) {
                Remove-Item Env:JARVIS_PS_NESTED -ErrorAction SilentlyContinue
            } else { $env:JARVIS_PS_NESTED = $prevNested }
        }
        Jarvis-Finish ([int]$global:JARVIS_LAST_EXIT)
        return
}

switch ($Kind) {
    { $_ -in @("minimize_window","close_window","close_all") } {
        $script=Join-Path $PSScriptRoot "window-action.ps1"
        $result=Invoke-JarvisHiddenOutput -FilePath "powershell.exe" -ArgumentList @("-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-File",$script,$Kind)
        Jarvis-Finish ([int]$result.ExitCode)
        return
    }
    "minimize_all" {
        $script = Join-Path $PSScriptRoot "minimize-all.ps1"
        $result = Invoke-JarvisHiddenOutput -FilePath "powershell.exe" -ArgumentList @("-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", $script)
        Jarvis-Finish ([int]$result.ExitCode)
        return
    }
    "url" {
        $script = Join-Path $PSScriptRoot "open-url.ps1"
        $prevNested = $env:JARVIS_PS_NESTED
        $env:JARVIS_PS_NESTED = '1'
        $global:JARVIS_LAST_EXIT = 0
        try { & $script $Target } catch {
            if ("$($_.Exception.Message)" -notlike 'JARVIS_OPEN_URL_DONE:*') { throw }
        } finally {
            if ([string]::IsNullOrEmpty($prevNested)) {
                Remove-Item Env:JARVIS_PS_NESTED -ErrorAction SilentlyContinue
            } else { $env:JARVIS_PS_NESTED = $prevNested }
        }
        Jarvis-Finish ([int]$global:JARVIS_LAST_EXIT)
        return
    }
    "file" {
        if (-not (Test-Path -LiteralPath $Target)) {
            Write-Error "File not found: $Target"
            Jarvis-Finish 1
            return
        }
        if ((Get-Item -LiteralPath $Target).PSIsContainer) {
            Write-Error "Path is a folder - use kind 'folder': $Target"
            Jarvis-Finish 1
            return
        }
        Start-JarvisTarget $Target
        Jarvis-Finish 0
        return
    }
    "folder" {
        $script = Join-Path $PSScriptRoot "open-folder.ps1"
        if (-not (Test-Path -LiteralPath $script)) {
            Write-Warning "open-folder.ps1 not found: $script"
            Jarvis-Finish 1
            return
        }
        $expanded = [Environment]::ExpandEnvironmentVariables($Target).Trim().Trim('"')
        if ([string]::IsNullOrWhiteSpace($expanded)) {
            Write-Warning "Empty folder path"
            Jarvis-Finish 1
            return
        }
        $prevNested = $env:JARVIS_PS_NESTED
        $env:JARVIS_PS_NESTED = '1'
        $ok = $false
        try {
            if ($expanded -like "shell:*") {
                & $script -Path $expanded
                $ok = $true
            } elseif (-not (Test-Path -LiteralPath $expanded)) {
                Write-Warning "Folder not found: $expanded"
            } elseif (-not (Get-Item -LiteralPath $expanded).PSIsContainer) {
                Write-Warning "Path is a file - use kind 'file': $expanded"
            } else {
                & $script -Path $expanded
                $ok = $true
            }
        } catch {
            Write-Warning "Open folder failed: $($_.Exception.Message)"
            $ok = $false
        } finally {
            if ([string]::IsNullOrEmpty($prevNested)) {
                Remove-Item Env:JARVIS_PS_NESTED -ErrorAction SilentlyContinue
            } else { $env:JARVIS_PS_NESTED = $prevNested }
        }
        if ($ok) { Jarvis-Finish 0 } else { Jarvis-Finish 1 }
        return
    }
    "app" {
        if ($Target -match '^[a-zA-Z][a-zA-Z0-9+.-]*:') {
            Start-Process $Target | Out-Null
            Jarvis-Finish 0
            return
        }
        if (Test-Path -LiteralPath $Target) {
            Start-JarvisTarget $Target
            Jarvis-Finish 0
            return
        }
        $cmd = Get-Command $Target -ErrorAction SilentlyContinue
        if ($cmd -and $cmd.Source) {
            Start-JarvisTarget $cmd.Source
            Jarvis-Finish 0
            return
        }
        Start-Process $Target | Out-Null
        Jarvis-Finish 0
        return
    }
    "keys" {
        if ([string]::IsNullOrWhiteSpace($Target)) { throw "Empty keys sequence" }
        Send-KeysSequence $Target
        Jarvis-Finish 0
        return
    }
    "type" {
        Type-Text $Target
        Jarvis-Finish 0
        return
    }
    "mouse" {
        Invoke-Mouse $Target
        Jarvis-Finish 0
        return
    }
    "search" {
        if ([string]::IsNullOrWhiteSpace($Target)) { throw "Empty search query" }
        Invoke-Search $Target
        return
    }
    "wait" {
        $ms = 250
        if (-not [int]::TryParse($Target, [ref]$ms)) { $ms = 250 }
        if ($ms -lt 0) { $ms = 0 }
        if ($ms -gt 60000) { $ms = 60000 }
        Start-Sleep -Milliseconds $ms
        Jarvis-Finish 0
        return
    }
    "volume" {
        $pct = 50
        if (-not [int]::TryParse($Target, [ref]$pct)) { throw "Volume must be 0-100" }
        $volScript = Join-Path $PSScriptRoot "set-volume.ps1"
        $r = Invoke-JarvisHiddenOutput -FilePath "powershell.exe" -ArgumentList @(
            "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", $volScript, "$pct"
        )
        Jarvis-Finish ([int]$r.ExitCode)
        return
    }
    "clipboard" {
        $op = $Target.Trim().ToLowerInvariant()
        switch ($op) {
            "copy" { Send-KeysSequence "^c" }
            "paste" { Send-KeysSequence "^v" }
            "cut" { Send-KeysSequence "^x" }
            "select_all" { Send-KeysSequence "^a" }
            "undo" { Send-KeysSequence "^z" }
            "redo" { Send-KeysSequence "^y" }
            "delete" { Send-KeysSequence "{DEL}" }
            "enter" { Send-KeysSequence "{ENTER}" }
            "escape" { Send-KeysSequence "{ESC}" }
            "tab" { Send-KeysSequence "{TAB}" }
            default { throw "Unknown clipboard op: $Target" }
        }
        Jarvis-Finish 0
        return
    }
    "shell" {
        if ([string]::IsNullOrWhiteSpace($Target)) { throw "Empty shell command" }
        $r = Invoke-JarvisHiddenOutput -FilePath "powershell.exe" -ArgumentList @(
            "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", $Target
        )
        Jarvis-Finish ([int]$r.ExitCode)
        return
    }
    default {
        Write-Error "Unknown action kind: $Kind"
        Jarvis-Finish 1
        return
    }
}
