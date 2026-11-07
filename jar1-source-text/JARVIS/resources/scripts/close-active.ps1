# Close the ACTIVE foreground window (never JARVIS, never the desktop shell).
# Fast path: PostMessage close immediately; short poll; Alt+F4 only if still open.
param(
    [long]$ForceHwnd = 0
)
$ErrorActionPreference = "Stop"
if ($ForceHwnd -eq 0 -and $env:JARVIS_CLOSE_HWND) {
    try { $ForceHwnd = [int64]$env:JARVIS_CLOSE_HWND } catch { $ForceHwnd = 0 }
}
. (Join-Path $PSScriptRoot "_jarvis-last-target.ps1")
Initialize-JarvisLastTarget

$WM_CLOSE = 0x0010
$WM_SYSCOMMAND = 0x0112
$SC_CLOSE = 0xF060

Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class JarvisWinClose {
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
  [DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam, uint fuFlags, uint uTimeout, out IntPtr lpdwResult);
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);
  [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr hWnd, uint uCmd);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);

  public const uint SMTO_ABORTIFHUNG = 0x0002;

  public static string ClassOf(IntPtr hWnd) {
    var sb = new StringBuilder(256);
    GetClassName(hWnd, sb, sb.Capacity);
    return sb.ToString();
  }

  public static bool IsShellDesktop(IntPtr hWnd) {
    if (hWnd == IntPtr.Zero) return true;
    string c = ClassOf(hWnd);
    if (string.Equals(c, "Progman", StringComparison.OrdinalIgnoreCase)) return true;
    if (string.Equals(c, "WorkerW", StringComparison.OrdinalIgnoreCase)) return true;
    if (string.Equals(c, "Shell_TrayWnd", StringComparison.OrdinalIgnoreCase)) return true;
    if (string.Equals(c, "Shell_SecondaryTrayWnd", StringComparison.OrdinalIgnoreCase)) return true;
    if (string.Equals(c, "NotifyIconOverflowWindow", StringComparison.OrdinalIgnoreCase)) return true;
    if (string.Equals(c, "Windows.UI.Core.CoreWindow", StringComparison.OrdinalIgnoreCase)) return true;
    if (string.Equals(c, "ControlCenterWindow", StringComparison.OrdinalIgnoreCase)) return true;
    if (string.Equals(c, "ForegroundStaging", StringComparison.OrdinalIgnoreCase)) return true;
    return false;
  }

  public static bool IsExplorerFolder(IntPtr hWnd) {
    if (hWnd == IntPtr.Zero || !IsWindow(hWnd)) return false;
    string c = ClassOf(hWnd);
    return string.Equals(c, "CabinetWClass", StringComparison.OrdinalIgnoreCase)
        || string.Equals(c, "ExploreWClass", StringComparison.OrdinalIgnoreCase);
  }

  public static IntPtr ResolveCloseableRoot(IntPtr hWnd) {
    if (hWnd == IntPtr.Zero || !IsWindow(hWnd)) return IntPtr.Zero;
    if (IsShellDesktop(hWnd)) return IntPtr.Zero;
    IntPtr owner = GetWindow(hWnd, 4 /* GW_OWNER */);
    if (owner != IntPtr.Zero && IsWindow(owner) && !IsShellDesktop(owner) && IsWindowVisible(owner)) {
      if (IsExplorerFolder(owner) || ClassOf(owner).Length > 0) hWnd = owner;
    }
    return hWnd;
  }

  public static IntPtr FindTopExplorerFolder() {
    IntPtr found = IntPtr.Zero;
    EnumWindows((h, l) => {
      if (!IsWindowVisible(h) || IsIconic(h) || IsShellDesktop(h)) return true;
      if (!IsExplorerFolder(h)) return true;
      found = h;
      return false;
    }, IntPtr.Zero);
    return found;
  }

  public static IntPtr FindTopCloseableWindow() {
    IntPtr found = IntPtr.Zero;
    EnumWindows((h, l) => {
      if (!IsWindowVisible(h) || IsIconic(h) || IsShellDesktop(h)) return true;
      found = h;
      return false;
    }, IntPtr.Zero);
    return found;
  }

  public static bool Gone(IntPtr hWnd) {
    return hWnd == IntPtr.Zero || !IsWindow(hWnd) || !IsWindowVisible(hWnd);
  }
}
"@ -ErrorAction Stop

function Test-IsJarvisOrShell([IntPtr]$hwnd) {
    if ($hwnd -eq [IntPtr]::Zero) { return $true }
    if ([JarvisWinClose]::IsShellDesktop($hwnd)) { return $true }
    if ([JarvisLastTarget]::IsJarvisHwnd($hwnd)) { return $true }
    $proc = [JarvisLastTarget]::ProcName($hwnd)
    if ($proc -match '^(?i)(ShellHost|ShellExperienceHost|StartMenuExperienceHost|SearchHost|TextInputHost)$') {
        return $true
    }
    return $false
}

function Test-JarvisLastTargetFresh {
    param([int]$MaxAgeSec = 180)
    $saved = Get-JarvisLastTarget
    if ($null -eq $saved) { return $false }
    try {
        $ts = [int64]$saved.ts
        if ($ts -le 0) { return $false }
        $age = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - $ts
        return ($age -ge 0 -and $age -le $MaxAgeSec)
    } catch {
        return $false
    }
}

function Resolve-JarvisSavedTargetHwnd {
    $saved = Get-JarvisLastTarget
    if ($null -eq $saved) { return [IntPtr]::Zero }
    try {
        $n = [int64]$saved.hwnd
        if ($n -ne 0) {
            $h = [IntPtr]$n
            if ([JarvisLastTarget]::IsWindow($h) -and -not [JarvisLastTarget]::IsJarvisHwnd($h)) {
                return $h
            }
        }
    } catch {}
    $kind = ([string]$saved.kind).ToLowerInvariant()
    $keywords = @(Get-JarvisLastKeywords)
    if ($kind -eq "explorer") {
        if ($keywords.Count -gt 0) {
            $h = [JarvisLastTarget]::FindExplorerByKeywords([string[]]$keywords, $true)
            if ($h -ne [IntPtr]::Zero) { return $h }
        }
        return [JarvisLastTarget]::FindTopExplorerFolder($true)
    }
    if ($keywords.Count -gt 0) {
        $h = [JarvisLastTarget]::FindByKeywords([string[]]$keywords, $true)
        if ($h -ne [IntPtr]::Zero) { return $h }
    }
    return [IntPtr]::Zero
}

function Get-ActiveCloseTarget {
    Initialize-JarvisLastTarget

    $saved = Get-JarvisLastTarget
    $savedKind = if ($null -ne $saved) { ([string]$saved.kind).ToLowerInvariant() } else { "" }
    $savedFresh = Test-JarvisLastTargetFresh -MaxAgeSec 180
    $savedHwnd = [IntPtr]::Zero
    if ($savedFresh -or $savedKind -eq "explorer") {
        $savedHwnd = Resolve-JarvisSavedTargetHwnd
        if ($savedHwnd -ne [IntPtr]::Zero -and (Test-IsJarvisOrShell $savedHwnd)) {
            $savedHwnd = [IntPtr]::Zero
        }
    }

    $fg = [JarvisLastTarget]::GetForegroundWindow()
    if ($fg -ne [IntPtr]::Zero -and [JarvisLastTarget]::IsJarvisHwnd($fg)) {
        [JarvisLastTarget]::YieldJarvis()
        Start-Sleep -Milliseconds 20
        $fg = [JarvisLastTarget]::GetForegroundWindow()
    }

    $fgRoot = [IntPtr]::Zero
    if ($fg -ne [IntPtr]::Zero) {
        $cand = [JarvisWinClose]::ResolveCloseableRoot($fg)
        if ($cand -ne [IntPtr]::Zero -and -not (Test-IsJarvisOrShell $cand)) {
            if ([JarvisLastTarget]::ProcName($cand) -match '^(?i)explorer$' -and -not [JarvisWinClose]::IsExplorerFolder($cand)) {
                $ex = [JarvisWinClose]::FindTopExplorerFolder()
                if ($ex -ne [IntPtr]::Zero) { $cand = $ex }
            }
            $fgRoot = $cand
        }
    }

    $fgIsBrowser = ($fgRoot -ne [IntPtr]::Zero) -and [JarvisLastTarget]::IsBrowserHwnd($fgRoot)
    $savedIsNonBrowser = ($savedHwnd -ne [IntPtr]::Zero) -and (
        $savedKind -eq "explorer" -or $savedKind -eq "app" -or -not [JarvisLastTarget]::IsBrowserHwnd($savedHwnd)
    )

    if ($savedFresh -and $savedIsNonBrowser -and $fgIsBrowser) {
        $root = [JarvisWinClose]::ResolveCloseableRoot($savedHwnd)
        if ($root -ne [IntPtr]::Zero -and -not (Test-IsJarvisOrShell $root)) {
            Write-Host "JARVIS close-active: prefer last-target kind=$savedKind over browser FG"
            return $root
        }
    }

    if ($fgRoot -ne [IntPtr]::Zero) {
        Write-Host "JARVIS close-active: prefer foreground"
        return $fgRoot
    }

    if ([JarvisWinClose]::IsShellDesktop($fg)) {
        if ($savedHwnd -ne [IntPtr]::Zero) {
            $root = [JarvisWinClose]::ResolveCloseableRoot($savedHwnd)
            if ($root -ne [IntPtr]::Zero -and -not (Test-IsJarvisOrShell $root)) {
                Write-Host "JARVIS close-active: desktop FG -> last-target"
                return $root
            }
        }
        $ex = [JarvisWinClose]::FindTopExplorerFolder()
        if ($ex -ne [IntPtr]::Zero) { return $ex }
    }

    if ($savedHwnd -ne [IntPtr]::Zero) {
        $h = [JarvisWinClose]::ResolveCloseableRoot($savedHwnd)
        if ($h -ne [IntPtr]::Zero -and -not (Test-IsJarvisOrShell $h)) {
            Write-Host "JARVIS close-active: fallback last-target"
            return $h
        }
    }

    $ex2 = [JarvisWinClose]::FindTopExplorerFolder()
    if ($ex2 -ne [IntPtr]::Zero) { return $ex2 }

    $top = [JarvisWinClose]::FindTopCloseableWindow()
    if ($top -ne [IntPtr]::Zero -and -not (Test-IsJarvisOrShell $top)) { return $top }

    return [IntPtr]::Zero
}

function Wait-WindowGone([IntPtr]$hwnd, [int]$Tries = 4, [int]$Ms = 18) {
    for ($i = 0; $i -lt $Tries; $i++) {
        if ([JarvisWinClose]::Gone($hwnd)) { return $true }
        Start-Sleep -Milliseconds $Ms
    }
    return [JarvisWinClose]::Gone($hwnd)
}

function Close-WindowHard([IntPtr]$hwnd) {
    $proc = [JarvisLastTarget]::ProcName($hwnd)
    $cls = [JarvisWinClose]::ClassOf($hwnd)
    $title = [JarvisLastTarget]::TitleOf($hwnd)
    Write-Host "JARVIS close-active: target proc=$proc class=$cls title=$title"

    $fg = [JarvisLastTarget]::GetForegroundWindow()
    if ($fg -ne $hwnd) {
        [void][JarvisLastTarget]::FocusWindow($hwnd)
    }

    # Fire close messages immediately (async).
    [void][JarvisWinClose]::PostMessage($hwnd, $WM_SYSCOMMAND, [IntPtr]$SC_CLOSE, [IntPtr]::Zero)
    [void][JarvisWinClose]::PostMessage($hwnd, $WM_CLOSE, [IntPtr]::Zero, [IntPtr]::Zero)

    if (Wait-WindowGone $hwnd 3 16) {
        Write-Host "JARVIS close-active: PostMessage close"
        return $true
    }

    $ignored = [IntPtr]::Zero
    [void][JarvisWinClose]::SendMessageTimeout(
        $hwnd, $WM_CLOSE, [IntPtr]::Zero, [IntPtr]::Zero,
        [JarvisWinClose]::SMTO_ABORTIFHUNG, 60, [ref]$ignored
    )
    if (Wait-WindowGone $hwnd 3 16) {
        Write-Host "JARVIS close-active: SendMessageTimeout WM_CLOSE"
        return $true
    }

    if ([JarvisLastTarget]::GetForegroundWindow() -ne $hwnd) {
        [void][JarvisLastTarget]::FocusWindow($hwnd)
    }
    [JarvisLastTarget]::ChordFast([JarvisLastTarget]::VK_MENU, [JarvisLastTarget]::VK_F4)
    if (Wait-WindowGone $hwnd 4 18) {
        Write-Host "JARVIS close-active: Alt+F4"
        return $true
    }

    Write-Host "JARVIS close-active: window still open (app may have blocked close)"
    return $false
}

$target = [IntPtr]::Zero
if ($ForceHwnd -ne 0) {
    $forced = [IntPtr]$ForceHwnd
    if ([JarvisLastTarget]::IsWindow($forced) -and -not (Test-IsJarvisOrShell $forced)) {
        Write-Host "JARVIS close-active: target=forced"
        $target = [JarvisWinClose]::ResolveCloseableRoot($forced)
        if ($target -eq [IntPtr]::Zero) { $target = $forced }
    } else {
        Write-Host "JARVIS close-active: forced hwnd rejected (missing or jarvis/shell)"
    }
}
if ($target -eq [IntPtr]::Zero) {
    $target = Get-ActiveCloseTarget
}
if ($target -eq [IntPtr]::Zero) {
    Write-Host "JARVIS close-active: no target window"
    exit 0
}

$ok = Close-WindowHard $target
if ($ok) {
    try {
        $path = Get-JarvisLastTargetPath
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
    } catch {}
}
exit 0
