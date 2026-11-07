# Last window/tab JARVIS opened. Close / pause / minimize target this, not z-order luck.
# Dot-source from other scripts. ASCII-only source (titles may be Unicode at runtime).

. (Join-Path $PSScriptRoot "_jarvis-data-dir.ps1")

function Get-JarvisLastTargetPath {
    return (Join-Path (Get-JarvisDataDir) "last-target.json")
}

function Initialize-JarvisLastTarget {
    if ("JarvisLastTarget" -as [type]) { return }
    if (Get-Command Set-JarvisAsciiTemp -ErrorAction SilentlyContinue) {
        [void](Set-JarvisAsciiTemp)
    } else {
        $asciiTemp = "C:\ProgramData\JARVIS\pscache"
        try {
            New-Item -ItemType Directory -Force -Path $asciiTemp | Out-Null
            $env:TEMP = $asciiTemp
            $env:TMP = $asciiTemp
        } catch {}
    }
    Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Collections.Generic;

public static class JarvisLastTarget {
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool AllowSetForegroundWindow(int dwProcessId);
  [DllImport("user32.dll")] public static extern bool LockSetForegroundWindow(uint uLockCode);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern void SwitchToThisWindow(IntPtr hWnd, bool fAltTab);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int X, int Y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr extra);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)]
  public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int max);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)]
  public static extern int GetClassName(IntPtr hWnd, StringBuilder name, int max);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);

  [StructLayout(LayoutKind.Sequential)]
  public struct RECT { public int Left, Top, Right, Bottom; }

  public const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
  public const uint MOUSEEVENTF_LEFTUP = 0x0004;
  public const uint KEYEVENTF_KEYUP = 0x0002;
  public const uint LSFW_UNLOCK = 2;
  public const uint SWP_NOSIZE = 0x0001;
  public const uint SWP_NOMOVE = 0x0002;
  public const uint SWP_SHOWWINDOW = 0x0040;
  static readonly IntPtr HWND_TOP = IntPtr.Zero;
  static readonly IntPtr HWND_TOPMOST = new IntPtr(-1);
  static readonly IntPtr HWND_NOTOPMOST = new IntPtr(-2);

  public const byte VK_CONTROL = 0x11;
  public const byte VK_SHIFT = 0x10;
  public const byte VK_MENU = 0x12;
  public const byte VK_TAB = 0x09;
  public const byte VK_SPACE = 0x20;
  public const byte VK_ESCAPE = 0x1B;
  public const byte VK_LEFT = 0x25;
  public const byte VK_UP = 0x26;
  public const byte VK_RIGHT = 0x27;
  public const byte VK_LWIN = 0x5B;
  public const byte VK_F4 = 0x73;
  public const byte VK_F5 = 0x74;
  public const byte VK_F11 = 0x7A;
  public const byte VK_A = 0x41;
  public const byte VK_D = 0x44;
  public const byte VK_F = 0x46;
  public const byte VK_H = 0x48;
  public const byte VK_J = 0x4A;
  public const byte VK_K = 0x4B;
  public const byte VK_L = 0x4C;
  public const byte VK_N = 0x4E;
  public const byte VK_P = 0x50;
  public const byte VK_T = 0x54;
  public const byte VK_W = 0x57;
  public const byte VK_OEM_PLUS = 0xBB;
  public const byte VK_OEM_MINUS = 0xBD;

  static readonly HashSet<string> BrowserProcs = new HashSet<string>(StringComparer.OrdinalIgnoreCase) {
    "chrome", "msedge", "firefox", "opera", "opera_gx", "brave", "browser", "yandex", "vivaldi",
    "chromium", "waterfox", "librewolf", "arc", "sidekick", "whale", "maxthon", "iridium",
    "slimjet", "avgbrowser", "avastbrowser", "torch", "comodo_dragon", "srwareiron"
  };

  static bool IsJarvisProcess(string name) {
    name = (name ?? "").ToLowerInvariant();
    return name == "jarvis-gui" || name == "jarvis-app" || name == "jarvis-run" || name == "jarvis-gestures";
  }

  public static string ProcName(IntPtr hWnd) {
    uint pid = 0;
    GetWindowThreadProcessId(hWnd, out pid);
    if (pid == 0) return "";
    try { return Process.GetProcessById((int)pid).ProcessName; }
    catch { return ""; }
  }

  public static string TitleOf(IntPtr hWnd) {
    var title = new StringBuilder(512);
    GetWindowText(hWnd, title, title.Capacity);
    return title.ToString();
  }

  public static bool IsJarvisHwnd(IntPtr hWnd) {
    if (hWnd == IntPtr.Zero) return false;
    if (IsJarvisProcess(ProcName(hWnd))) return true;
    // Title heuristic must NOT treat Explorer folders like "JARVIS Screenshots"
    // or browser tabs as the assistant UI.
    string proc = ProcName(hWnd);
    if (BrowserProcs.Contains(proc)) return false;
    if (string.Equals(proc, "explorer", StringComparison.OrdinalIgnoreCase)) return false;
    var t = TitleOf(hWnd);
    if (t.IndexOf("JARVIS Screenshots", StringComparison.OrdinalIgnoreCase) >= 0) return false;
    return t.IndexOf("JARVIS", StringComparison.OrdinalIgnoreCase) >= 0
        && t.IndexOf("YouTube", StringComparison.OrdinalIgnoreCase) < 0;
  }

  public static bool IsBrowserHwnd(IntPtr hWnd) {
    if (hWnd == IntPtr.Zero || !IsWindow(hWnd) || !IsWindowVisible(hWnd)) return false;
    if (IsJarvisHwnd(hWnd)) return false;
    return BrowserProcs.Contains(ProcName(hWnd));
  }

  static bool IsBrowserCandidate(IntPtr hWnd, bool allowIconic) {
    if (!IsWindow(hWnd) || !IsWindowVisible(hWnd)) return false;
    if (!allowIconic && IsIconic(hWnd)) return false;
    if (!IsBrowserHwnd(hWnd)) return false;
    if (TitleOf(hWnd).Length < 1) return false;
    var cls = new StringBuilder(256);
    GetClassName(hWnd, cls, cls.Capacity);
    var c = cls.ToString();
    if (c.IndexOf("Chrome_WidgetWin_2", StringComparison.OrdinalIgnoreCase) >= 0) return false;
    return true;
  }

  public static bool TitleMatches(string title, string[] keywords) {
    if (string.IsNullOrEmpty(title) || keywords == null) return false;
    foreach (var raw in keywords) {
      var k = (raw ?? "").Trim();
      if (k.Length < 3) continue;
      if (title.IndexOf(k, StringComparison.OrdinalIgnoreCase) >= 0) return true;
    }
    return false;
  }

  public static IntPtr FindTopBrowser(bool allowIconic) {
    IntPtr found = IntPtr.Zero;
    EnumWindows((hWnd, l) => {
      if (!IsBrowserCandidate(hWnd, allowIconic)) return true;
      found = hWnd;
      return false;
    }, IntPtr.Zero);
    return found;
  }

  static bool ProcAllowed(IntPtr hWnd, string[] procs) {
    if (procs == null || procs.Length == 0) return true;
    string p = ProcName(hWnd);
    foreach (var raw in procs) {
      var want = (raw ?? "").Trim();
      if (want.Length < 1) continue;
      if (string.Equals(p, want, StringComparison.OrdinalIgnoreCase)) return true;
    }
    return false;
  }

  public static IntPtr FindTopBrowserInProcs(string[] procs, bool allowIconic) {
    IntPtr found = IntPtr.Zero;
    EnumWindows((hWnd, l) => {
      if (!IsBrowserCandidate(hWnd, allowIconic)) return true;
      if (!ProcAllowed(hWnd, procs)) return true;
      found = hWnd;
      return false;
    }, IntPtr.Zero);
    return found;
  }

  public static IntPtr FindExplorerByKeywords(string[] keywords, bool allowIconic) {
    IntPtr found = IntPtr.Zero;
    EnumWindows((hWnd, l) => {
      if (!IsWindowVisible(hWnd)) return true;
      if (!allowIconic && IsIconic(hWnd)) return true;
      var cls = new StringBuilder(256);
      GetClassName(hWnd, cls, cls.Capacity);
      string c = cls.ToString();
      if (!string.Equals(c, "CabinetWClass", StringComparison.OrdinalIgnoreCase)
          && !string.Equals(c, "ExploreWClass", StringComparison.OrdinalIgnoreCase)) {
        return true;
      }
      if (keywords != null && keywords.Length > 0) {
        if (!TitleMatches(TitleOf(hWnd), keywords)) return true;
      }
      found = hWnd;
      return false;
    }, IntPtr.Zero);
    return found;
  }

  public static IntPtr FindTopExplorerFolder(bool allowIconic) {
    return FindExplorerByKeywords(null, allowIconic);
  }

  public static IntPtr FindByKeywords(string[] keywords, bool allowIconic) {
    IntPtr found = IntPtr.Zero;
    EnumWindows((hWnd, l) => {
      if (!IsBrowserCandidate(hWnd, allowIconic)) return true;
      if (!TitleMatches(TitleOf(hWnd), keywords)) return true;
      found = hWnd;
      return false;
    }, IntPtr.Zero);
    return found;
  }

  public static IntPtr FindByKeywordsInProcs(string[] keywords, string[] procs, bool allowIconic) {
    IntPtr found = IntPtr.Zero;
    EnumWindows((hWnd, l) => {
      if (!IsBrowserCandidate(hWnd, allowIconic)) return true;
      if (!ProcAllowed(hWnd, procs)) return true;
      if (!TitleMatches(TitleOf(hWnd), keywords)) return true;
      found = hWnd;
      return false;
    }, IntPtr.Zero);
    return found;
  }

  public static IntPtr Resolve(long savedHwnd, string[] keywords) {
    IntPtr byKw = FindByKeywords(keywords, false);
    if (byKw != IntPtr.Zero) return byKw;
    byKw = FindByKeywords(keywords, true);
    if (byKw != IntPtr.Zero) return byKw;

    IntPtr saved = IntPtr.Zero;
    try { saved = new IntPtr(savedHwnd); } catch { saved = IntPtr.Zero; }
    if (saved != IntPtr.Zero && IsWindow(saved) && IsBrowserCandidate(saved, true)) return saved;

    IntPtr top = FindTopBrowser(false);
    if (top != IntPtr.Zero) return top;
    return FindTopBrowser(true);
  }

  public static void YieldJarvis() {
    EnumWindows((hWnd, l) => {
      if (!IsWindowVisible(hWnd) || !IsJarvisHwnd(hWnd)) return true;
      ShowWindow(hWnd, 6); // SW_MINIMIZE
      return true;
    }, IntPtr.Zero);
  }

  /// Call right before Start-Process so the new window can legally take FG.
  public static void UnlockForeground() {
    AllowSetForegroundWindow(-1);
    LockSetForegroundWindow(LSFW_UNLOCK);
  }

  static bool IsMainCandidate(IntPtr hWnd, bool allowIconic) {
    if (!IsWindow(hWnd) || !IsWindowVisible(hWnd)) return false;
    if (!allowIconic && IsIconic(hWnd)) return false;
    if (IsJarvisHwnd(hWnd)) return false;
    var cls = new StringBuilder(256);
    GetClassName(hWnd, cls, cls.Capacity);
    var c = cls.ToString();
    if (c.IndexOf("Chrome_WidgetWin_2", StringComparison.OrdinalIgnoreCase) >= 0) return false;
    if (c == "Shell_TrayWnd" || c == "NotifyIconOverflowWindow" || c == "Progman") return false;
    RECT r;
    if (!GetWindowRect(hWnd, out r)) return false;
    int w = r.Right - r.Left;
    int h = r.Bottom - r.Top;
    return w >= 80 && h >= 80;
  }

  public static IntPtr FindTopByProcs(string[] procs, bool allowIconic) {
    IntPtr found = IntPtr.Zero;
    EnumWindows((hWnd, l) => {
      if (!IsMainCandidate(hWnd, allowIconic)) return true;
      if (!ProcAllowed(hWnd, procs)) return true;
      found = hWnd;
      return false;
    }, IntPtr.Zero);
    return found;
  }

  static void AttachPair(uint a, uint b, bool on) {
    if (a == 0 || b == 0 || a == b) return;
    AttachThreadInput(a, b, on);
  }

  public static bool FocusWindow(IntPtr hWnd) {
    if (hWnd == IntPtr.Zero || !IsWindow(hWnd)) return false;
    uint pid = 0;
    GetWindowThreadProcessId(hWnd, out pid);
    try { AllowSetForegroundWindow((int)pid); } catch {}
    UnlockForeground();

    // NEVER ShowWindow(SW_RESTORE) on a maximized/normal window - it un-maximizes
    // and shrinks Chrome/Edge (felt as "уменьшил окно" on tab commands).
    // Restore only when actually minimized; show only when hidden.
    if (IsIconic(hWnd)) {
      ShowWindowAsync(hWnd, 9); // SW_RESTORE - minimized only
      ShowWindow(hWnd, 9);
    } else if (!IsWindowVisible(hWnd)) {
      ShowWindow(hWnd, 5); // SW_SHOW
    }
    // Maximized (IsZoomed) and normal visible windows: leave size alone.

    IntPtr fg = GetForegroundWindow();
    if (IsJarvisHwnd(fg)) YieldJarvis();

    // Already foreground and not minimized - do not flash TOPMOST / resize path.
    if (fg == hWnd && !IsIconic(hWnd)) return true;

    uint unused = 0;
    uint curTid = GetCurrentThreadId();
    uint fgTid = fg != IntPtr.Zero ? GetWindowThreadProcessId(fg, out unused) : 0;
    uint targetTid = GetWindowThreadProcessId(hWnd, out unused);

    AttachPair(curTid, fgTid, true);
    AttachPair(curTid, targetTid, true);
    AttachPair(fgTid, targetTid, true);

    // Do NOT tap Alt - it opens the menu bar so Ctrl+W / Alt+F4 misfire.
    SwitchToThisWindow(hWnd, true);
    BringWindowToTop(hWnd);
    // SWP_NOSIZE | SWP_NOMOVE - never change window geometry while focusing.
    SetWindowPos(hWnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
    bool ok = SetForegroundWindow(hWnd);
    SetWindowPos(hWnd, HWND_NOTOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
    SetWindowPos(hWnd, HWND_TOP, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
    // Second pass: some Chromium builds steal FG only after TOPMOST flash.
    if (GetForegroundWindow() != hWnd) {
      SwitchToThisWindow(hWnd, true);
      BringWindowToTop(hWnd);
      ok = SetForegroundWindow(hWnd) || ok;
    }

    AttachPair(fgTid, targetTid, false);
    AttachPair(curTid, targetTid, false);
    AttachPair(curTid, fgTid, false);

    IntPtr now = GetForegroundWindow();
    return ok || now == hWnd;
  }

  public static bool WaitForeground(IntPtr hWnd, int tries) {
    return WaitForegroundExact(hWnd, tries);
  }

  /// Require the exact HWND to be foreground (not "any browser").
  public static bool WaitForegroundExact(IntPtr hWnd, int tries) {
    for (int i = 0; i < tries; i++) {
      if (IsJarvisHwnd(GetForegroundWindow())) YieldJarvis();
      if (FocusWindow(hWnd)) {
        IntPtr now = GetForegroundWindow();
        if (IsJarvisHwnd(now)) {
          System.Threading.Thread.Sleep(40);
          continue;
        }
        if (now == hWnd) return true;
      }
      System.Threading.Thread.Sleep(50);
    }
    return GetForegroundWindow() == hWnd;
  }

  static void Down(byte vk) { keybd_event(vk, 0, 0, UIntPtr.Zero); }
  static void Up(byte vk) { keybd_event(vk, 0, KEYEVENTF_KEYUP, UIntPtr.Zero); }
  public static void Tap(byte vk) {
    Down(vk);
    System.Threading.Thread.Sleep(25);
    Up(vk);
  }
  public static void Chord(params byte[] keys) {
    foreach (var k in keys) {
      Down(k);
      System.Threading.Thread.Sleep(12);
    }
    System.Threading.Thread.Sleep(30);
    for (int i = keys.Length - 1; i >= 0; i--) {
      Up(keys[i]);
      System.Threading.Thread.Sleep(12);
    }
  }
  /// Faster chords for tab/window close (Ctrl+W / Alt+F4) - still reliable on Chromium.
  public static void ChordFast(params byte[] keys) {
    foreach (var k in keys) {
      Down(k);
      System.Threading.Thread.Sleep(4);
    }
    System.Threading.Thread.Sleep(10);
    for (int i = keys.Length - 1; i >= 0; i--) {
      Up(keys[i]);
      System.Threading.Thread.Sleep(4);
    }
  }

  /// Click lower-center of browser window so YouTube player receives K (not address bar).
  public static void ClickVideoArea(IntPtr hWnd) {
    if (hWnd == IntPtr.Zero || !IsWindow(hWnd)) return;
    RECT r;
    if (!GetWindowRect(hWnd, out r)) return;
    int w = r.Right - r.Left;
    int h = r.Bottom - r.Top;
    if (w < 80 || h < 80) return;
    int x = r.Left + w / 2;
    int y = r.Top + (int)(h * 0.55);
    SetCursorPos(x, y);
    System.Threading.Thread.Sleep(35);
    mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, UIntPtr.Zero);
    System.Threading.Thread.Sleep(20);
    mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, UIntPtr.Zero);
    System.Threading.Thread.Sleep(50);
  }
}
"@
}

function Get-JarvisUrlKeywords {
    param([string]$Url)
    $list = New-Object System.Collections.Generic.List[string]
    if ([string]::IsNullOrWhiteSpace($Url)) { return @() }
    $u = $Url.ToLowerInvariant()

    function Add-Kw([string]$k) {
        if ([string]::IsNullOrWhiteSpace($k)) { return }
        $k = $k.Trim()
        if ($k.Length -lt 3) { return }
        if (-not $list.Contains($k)) { [void]$list.Add($k) }
    }

    if ($u -match 'youtube\.com|youtu\.be') {
        Add-Kw 'youtube'
        Add-Kw 'youtu'
    }
    if ($u -match 'music\.youtube') { Add-Kw 'youtube music' }
    if ($u -match 'yandex\.') { Add-Kw 'yandex' }
    if ($u -match 'wikipedia\.org') { Add-Kw 'wikipedia' }
    if ($u -match 'google\.') { Add-Kw 'google' }
    if ($u -match 'instagram\.') { Add-Kw 'instagram' }
    if ($u -match 'tiktok\.') { Add-Kw 'tiktok' }
    if ($u -match 'twitch\.') { Add-Kw 'twitch' }
    if ($u -match 'netflix\.') { Add-Kw 'netflix' }
    if ($u -match 'rutube\.') { Add-Kw 'rutube' }
    if ($u -match 'vk\.(com|ru)') { Add-Kw 'vk' }
    if ($u -match 'chatgpt\.|openai\.') { Add-Kw 'chatgpt' }
    if ($u -match 'github\.') { Add-Kw 'github' }
    if ($u -match 'gmail\.|mail\.google') { Add-Kw 'gmail' }

    try {
        $uri = [Uri]$Url
        $hostName = $uri.Host -replace '^www\.', ''
        $parts = $hostName -split '\.'
        if ($parts.Count -ge 1) { Add-Kw $parts[0] }
    } catch {}

    return @($list.ToArray())
}

function Save-JarvisLastTarget {
    param(
        [IntPtr]$Hwnd = [IntPtr]::Zero,
        [string]$Process = "",
        [string]$Title = "",
        [string]$Url = "",
        [string[]]$Keywords = @(),
        [string]$Kind = "browser"
    )
    $dir = Get-JarvisDataDir
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $hwndNum = 0
    try { $hwndNum = $Hwnd.ToInt64() } catch { $hwndNum = 0 }
    $obj = [ordered]@{
        hwnd     = $hwndNum
        process  = $Process
        title    = $Title
        url      = $Url
        keywords = @($Keywords)
        kind     = $Kind
        ts       = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    }
    $json = $obj | ConvertTo-Json -Compress
    [IO.File]::WriteAllText((Get-JarvisLastTargetPath), $json, [Text.UTF8Encoding]::new($false))
}

function Get-JarvisLastTarget {
    $path = Get-JarvisLastTargetPath
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try {
        $raw = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
        return ($raw | ConvertFrom-Json)
    } catch {
        return $null
    }
}

function Get-JarvisLastKeywords {
    $t = Get-JarvisLastTarget
    if ($null -eq $t) { return @() }
    $kw = @()
    if ($t.keywords) { $kw = @($t.keywords | ForEach-Object { [string]$_ }) }
    if ($kw.Count -lt 1 -and $t.url) { $kw = @(Get-JarvisUrlKeywords ([string]$t.url)) }
    return @($kw)
}

function Get-JarvisBrowserProcessNames {
    param([string]$Browser)
    $name = if ($null -eq $Browser) { "" } else { [string]$Browser }
    switch ($name.ToLowerInvariant()) {
        "chrome"  { return @("chrome") }
        "edge"    { return @("msedge") }
        "firefox" { return @("firefox") }
        "opera"   { return @("opera", "opera_gx") }
        "brave"   { return @("brave") }
        "yandex"  { return @("browser", "yandex") }
        default   { return @() }
    }
}

function Invoke-JarvisPrepareOpen {
    Initialize-JarvisLastTarget
    try { [JarvisLastTarget]::UnlockForeground() } catch {
        try { [void][JarvisLastTarget]::AllowSetForegroundWindow(-1) } catch {}
        try { [void][JarvisLastTarget]::LockSetForegroundWindow(2) } catch {}
    }
    try { [JarvisLastTarget]::YieldJarvis() } catch {}
}

function Find-JarvisTopByProcs {
    param(
        [string[]]$ProcessNames,
        [bool]$AllowIconic = $true
    )
    Initialize-JarvisLastTarget
    $names = [string[]](@($ProcessNames | Where-Object { $_ }))
    if ($names.Count -lt 1) { return [IntPtr]::Zero }
    try {
        return [JarvisLastTarget]::FindTopByProcs($names, $AllowIconic)
    } catch {
        $script:jarvisFoundProcHwnd = [IntPtr]::Zero
        $script:jarvisWantProcs = $names
        $script:jarvisAllowIconic = $AllowIconic
        $cb = [JarvisLastTarget+EnumWindowsProc] {
            param([IntPtr]$h, [IntPtr]$l)
            if (-not [JarvisLastTarget]::IsWindow($h)) { return $true }
            if (-not [JarvisLastTarget]::IsWindowVisible($h)) { return $true }
            if (-not $script:jarvisAllowIconic -and [JarvisLastTarget]::IsIconic($h)) { return $true }
            if ([JarvisLastTarget]::IsJarvisHwnd($h)) { return $true }
            $p = [JarvisLastTarget]::ProcName($h)
            foreach ($want in @($script:jarvisWantProcs)) {
                if ($p -and $want -and ($p -ieq $want)) {
                    $script:jarvisFoundProcHwnd = $h
                    return $false
                }
            }
            return $true
        }
        [void][JarvisLastTarget]::EnumWindows($cb, [IntPtr]::Zero)
        return $script:jarvisFoundProcHwnd
    }
}

function Register-JarvisOpenedApp {
    param(
        [Parameter(Mandatory = $true)][string[]]$ProcessNames,
        [int]$TimeoutMs = 1500
    )
    Initialize-JarvisLastTarget
    Invoke-JarvisPrepareOpen
    $names = [string[]](@($ProcessNames | Where-Object { $_ }))
    if ($names.Count -lt 1) { return }
    $hwnd = [IntPtr]::Zero
    $deadline = [datetime]::UtcNow.AddMilliseconds([Math]::Max(200, $TimeoutMs))
    $first = $true
    do {
        if (-not $first) { Start-Sleep -Milliseconds 35 }
        $first = $false
        $hwnd = Find-JarvisTopByProcs -ProcessNames $names -AllowIconic $true
        if ($hwnd -ne [IntPtr]::Zero) {
            [void][JarvisLastTarget]::FocusWindow($hwnd)
            if ([JarvisLastTarget]::GetForegroundWindow() -eq $hwnd) { break }
        }
    } while ([datetime]::UtcNow -lt $deadline)
    if ($hwnd -ne [IntPtr]::Zero) {
        [void][JarvisLastTarget]::WaitForegroundExact($hwnd, 8)
        $title = [JarvisLastTarget]::TitleOf($hwnd)
        $proc = [JarvisLastTarget]::ProcName($hwnd)
        Save-JarvisLastTarget -Hwnd $hwnd -Process $proc -Title $title -Url "" -Keywords $names -Kind "app"
        Write-Host "JARVIS last-target app: hwnd=$hwnd proc=$proc title=$title"
    } else {
        Write-Host "JARVIS last-target app: window not found procs=$($names -join ',')"
    }
}

function Register-JarvisOpenedFolder {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string[]]$TitleHints = @()
    )
    Initialize-JarvisLastTarget
    Invoke-JarvisPrepareOpen
    $leaf = [IO.Path]::GetFileName($Path.TrimEnd('\', '/'))
    if ([string]::IsNullOrWhiteSpace($leaf)) { $leaf = "Explorer" }
    $keywords = New-Object System.Collections.Generic.List[string]
    foreach ($h in @($TitleHints + @($leaf))) {
        if ([string]::IsNullOrWhiteSpace($h)) { continue }
        $t = ([string]$h).Trim()
        if ($t.Length -ge 3 -and -not $keywords.Contains($t)) { [void]$keywords.Add($t) }
    }
    $fileUrl = "file:///" + ($Path -replace '\\', '/')
    Save-JarvisLastTarget -Hwnd ([IntPtr]::Zero) -Process "explorer" -Title $leaf -Url $fileUrl -Keywords @($keywords.ToArray()) -Kind "explorer"

    $hwnd = [IntPtr]::Zero
    $title = ""
    $kwArr = [string[]]$keywords.ToArray()
    $hwnd = [JarvisLastTarget]::FindExplorerByKeywords($kwArr, $true)
    if ($hwnd -eq [IntPtr]::Zero -and $leaf.Length -ge 3) {
        $hwnd = [JarvisLastTarget]::FindExplorerByKeywords([string[]]@($leaf), $true)
    }
    if ($hwnd -eq [IntPtr]::Zero) {
        $hwnd = [JarvisLastTarget]::FindTopExplorerFolder($true)
    }
    if ($hwnd -ne [IntPtr]::Zero) {
        $title = [JarvisLastTarget]::TitleOf($hwnd)
        Save-JarvisLastTarget -Hwnd $hwnd -Process "explorer" -Title $title -Url $fileUrl -Keywords $kwArr -Kind "explorer"
        [void][JarvisLastTarget]::FocusWindow($hwnd)
    }
    for ($i = 0; $i -lt 18; $i++) {
        if ($i -gt 0) { Start-Sleep -Milliseconds 40 }
        $hit = [JarvisLastTarget]::FindExplorerByKeywords($kwArr, $true)
        if ($hit -eq [IntPtr]::Zero -and $leaf.Length -ge 3) {
            $hit = [JarvisLastTarget]::FindExplorerByKeywords([string[]]@($leaf), $true)
        }
        if ($hit -eq [IntPtr]::Zero) {
            $hit = [JarvisLastTarget]::FindTopExplorerFolder($true)
        }
        if ($hit -eq [IntPtr]::Zero) { continue }
        $hwnd = $hit
        $title = [JarvisLastTarget]::TitleOf($hit)
        Save-JarvisLastTarget -Hwnd $hwnd -Process "explorer" -Title $title -Url $fileUrl -Keywords $kwArr -Kind "explorer"
        [void][JarvisLastTarget]::FocusWindow($hit)
        if ([JarvisLastTarget]::TitleMatches($title, $kwArr)) { break }
        if ([JarvisLastTarget]::GetForegroundWindow() -eq $hit -and $i -ge 4) { break }
    }
    if ($hwnd -ne [IntPtr]::Zero) {
        [void][JarvisLastTarget]::WaitForegroundExact($hwnd, 8)
        Write-Host "JARVIS last-target folder: hwnd=$hwnd title=$title path=$Path"
    } else {
        Write-Host "JARVIS last-target folder: window not found yet path=$Path"
    }
}

function Register-JarvisOpenedUrl {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [string]$Browser = ""
    )
    Initialize-JarvisLastTarget
    Invoke-JarvisPrepareOpen
    $keywords = @(Get-JarvisUrlKeywords $Url)
    $procs = @(Get-JarvisBrowserProcessNames -Browser $Browser)
    # Snapshot existing browser HWNDs so we prefer a NEW window over an older YouTube tab.
    $script:jarvisBeforeHwnds = @{}
    try {
        $cb = [JarvisLastTarget+EnumWindowsProc] {
            param([IntPtr]$h, [IntPtr]$l)
            if ([JarvisLastTarget]::IsBrowserHwnd($h)) {
                $script:jarvisBeforeHwnds["$([int64]$h)"] = $true
            }
            return $true
        }
        [void][JarvisLastTarget]::EnumWindows($cb, [IntPtr]::Zero)
    } catch {
        $script:jarvisBeforeHwnds = @{}
        $top0 = [JarvisLastTarget]::FindTopBrowser($true)
        if ($top0 -ne [IntPtr]::Zero) { $script:jarvisBeforeHwnds["$([int64]$top0)"] = $true }
    }
    Save-JarvisLastTarget -Hwnd ([IntPtr]::Zero) -Process "" -Title "" -Url $Url -Keywords $keywords -Kind "browser"

    # Bring the browser to the front NOW. Waiting for the tab title used to take
    # ~6-10s; by then Windows denies SetForegroundWindow and only the taskbar flashes.
    $hwnd = [IntPtr]::Zero
    $title = ""
    $proc = ""
    if ($procs.Count -gt 0) {
        $hwnd = [JarvisLastTarget]::FindTopBrowserInProcs([string[]]$procs, $true)
    }
    if ($hwnd -eq [IntPtr]::Zero) {
        $hwnd = [JarvisLastTarget]::FindTopBrowser($true)
    }
    if ($hwnd -ne [IntPtr]::Zero) {
        $title = [JarvisLastTarget]::TitleOf($hwnd)
        $proc = [JarvisLastTarget]::ProcName($hwnd)
        Save-JarvisLastTarget -Hwnd $hwnd -Process $proc -Title $title -Url $Url -Keywords $keywords -Kind "browser"
        [void][JarvisLastTarget]::FocusWindow($hwnd)
    }

    $bestNew = [IntPtr]::Zero
    $bestNewTitle = ""
    $bestNewProc = ""
    $matched = [IntPtr]::Zero
    for ($i = 0; $i -lt 20; $i++) {
        if ($i -gt 0) { Start-Sleep -Milliseconds 40 }
        $hit = [IntPtr]::Zero
        if ($procs.Count -gt 0) {
            $hit = [JarvisLastTarget]::FindByKeywordsInProcs([string[]]$keywords, [string[]]$procs, $true)
            if ($hit -eq [IntPtr]::Zero) {
                $hit = [JarvisLastTarget]::FindTopBrowserInProcs([string[]]$procs, $true)
            }
        }
        if ($hit -eq [IntPtr]::Zero) {
            $hit = [JarvisLastTarget]::FindByKeywords([string[]]$keywords, $true)
        }
        if ($hit -eq [IntPtr]::Zero -and $procs.Count -lt 1) {
            $hit = [JarvisLastTarget]::FindTopBrowser($true)
        }
        if ($hit -eq [IntPtr]::Zero) { continue }

        $hwnd = $hit
        $title = [JarvisLastTarget]::TitleOf($hit)
        $proc = [JarvisLastTarget]::ProcName($hit)
        $isNew = -not $script:jarvisBeforeHwnds.ContainsKey("$([int64]$hit)")
        $titleOk = [JarvisLastTarget]::TitleMatches($title, [string[]]$keywords)

        if ($isNew -and $bestNew -eq [IntPtr]::Zero) {
            $bestNew = $hit
            $bestNewTitle = $title
            $bestNewProc = $proc
        }
        Save-JarvisLastTarget -Hwnd $hwnd -Process $proc -Title $title -Url $Url -Keywords $keywords -Kind "browser"
        [void][JarvisLastTarget]::FocusWindow($hit)
        if ($titleOk) {
            $matched = $hit
            break
        }
        if ($isNew -and $i -ge 6) { break }
        if ([JarvisLastTarget]::GetForegroundWindow() -eq $hit -and $i -ge 4) { break }
    }
    if ($matched -ne [IntPtr]::Zero) {
        $hwnd = $matched
    } elseif ($bestNew -ne [IntPtr]::Zero) {
        $hwnd = $bestNew
        $title = $bestNewTitle
        $proc = $bestNewProc
        Save-JarvisLastTarget -Hwnd $hwnd -Process $proc -Title $title -Url $Url -Keywords $keywords -Kind "browser"
        Write-Host "JARVIS last-target: preferred NEW hwnd=$hwnd"
    }
    if ($hwnd -ne [IntPtr]::Zero) {
        $focused = [JarvisLastTarget]::WaitForegroundExact($hwnd, 10)
        if (-not $focused) {
            [JarvisLastTarget]::YieldJarvis()
            $focused = [JarvisLastTarget]::WaitForegroundExact($hwnd, 6)
        }
        Write-Host "JARVIS last-target: hwnd=$($hwnd) focused=$focused proc=$proc title=$title url=$Url browser=$Browser"
    } else {
        Write-Host "JARVIS last-target: no window found url=$Url browser=$Browser"
    }
}

function Resolve-JarvisControlHwnd {
    Initialize-JarvisLastTarget
    $saved = Get-JarvisLastTarget
    $hwndNum = 0
    $keywords = @()
    if ($null -ne $saved) {
        try { $hwndNum = [int64]$saved.hwnd } catch { $hwndNum = 0 }
        $keywords = @(Get-JarvisLastKeywords)
    }
    $hwnd = [JarvisLastTarget]::Resolve([int64]$hwndNum, [string[]]$keywords)
    return $hwnd
}

function Invoke-JarvisFocusLastTab {
    param([switch]$NeedSpecificTab)
    Initialize-JarvisLastTarget

    # 1) Foreground browser first - what the user is looking at.
    # Do NOT re-focus / ShowWindow when already FG: that used to SW_RESTORE and shrink maximized browsers.
    $fg = [JarvisLastTarget]::GetForegroundWindow()
    if ($fg -ne [IntPtr]::Zero -and [JarvisLastTarget]::IsBrowserHwnd($fg) -and -not [JarvisLastTarget]::IsJarvisHwnd($fg)) {
        $title = [JarvisLastTarget]::TitleOf($fg)
        $keywords = @(Get-JarvisLastKeywords)
        $matched = [JarvisLastTarget]::TitleMatches($title, [string[]]$keywords)
        $youtube = [JarvisLastTarget]::TitleMatches($title, [string[]]@("youtube", "youtu")) -or (
            (@($keywords) | Where-Object { $_ -match 'youtu' }).Count -gt 0
        )
        Write-Host "JARVIS last-target: foreground browser already FG title=$title"
        $proc = [JarvisLastTarget]::ProcName($fg)
        $url = ""
        $saved = Get-JarvisLastTarget
        if ($null -ne $saved) { $url = [string]$saved.url }
        Save-JarvisLastTarget -Hwnd $fg -Process $proc -Title $title -Url $url -Keywords $keywords -Kind "browser"
        return @{ Ok = $true; Hwnd = $fg; Title = $title; Youtube = $youtube; Matched = $matched }
    }

    $hwnd = Resolve-JarvisControlHwnd
    if ($hwnd -eq [IntPtr]::Zero) {
        Write-Host "JARVIS last-target: no browser window"
        return @{ Ok = $false; Hwnd = [IntPtr]::Zero; Title = ""; Youtube = $false }
    }
    $ok = [JarvisLastTarget]::WaitForegroundExact($hwnd, 18)
    Start-Sleep -Milliseconds 70
    $title = [JarvisLastTarget]::TitleOf($hwnd)
    $keywords = @(Get-JarvisLastKeywords)
    $matched = [JarvisLastTarget]::TitleMatches($title, [string[]]$keywords)

    if ($NeedSpecificTab -and -not $matched -and $keywords.Count -gt 0) {
        # Never SendKeys search text - Russian keyboard layout types garbage ("youtube" -> "ютюбе").
        $safeKw = @($keywords | Where-Object {
            $_ -and $_ -match '^[a-z0-9][a-z0-9.\-]*$' -and $_.Length -ge 4
        })
        foreach ($kw in $safeKw) {
            $alt = [JarvisLastTarget]::FindByKeywords([string[]]@($kw), $false)
            if ($alt -eq [IntPtr]::Zero) {
                $alt = [JarvisLastTarget]::FindByKeywords([string[]]@($kw), $true)
            }
            if ($alt -ne [IntPtr]::Zero) {
                Write-Host "JARVIS last-target: found tab by keyword '$kw'"
                $hwnd = $alt
                [void][JarvisLastTarget]::WaitForegroundExact($hwnd, 12)
                $title = [JarvisLastTarget]::TitleOf($hwnd)
                $matched = [JarvisLastTarget]::TitleMatches($title, [string[]]$keywords)
                break
            }
        }
    }

    $fg2 = [JarvisLastTarget]::GetForegroundWindow()
    $fgJarvis = [JarvisLastTarget]::IsJarvisHwnd($fg2)
    $exactFg = ($fg2 -eq $hwnd)
    $youtube = [JarvisLastTarget]::TitleMatches($title, [string[]]@("youtube", "youtu")) -or (
        (@($keywords) | Where-Object { $_ -match 'youtu' }).Count -gt 0
    )
    Write-Host "JARVIS last-target: focused=$ok fgJarvis=$fgJarvis exactFg=$exactFg matched=$matched youtube=$youtube title=$title"
    $ok2 = $ok -and -not $fgJarvis -and $exactFg -and [JarvisLastTarget]::IsBrowserHwnd($hwnd)
    if ($ok2) {
        $proc = [JarvisLastTarget]::ProcName($hwnd)
        $url = ""
        $saved = Get-JarvisLastTarget
        if ($null -ne $saved) { $url = [string]$saved.url }
        Save-JarvisLastTarget -Hwnd $hwnd -Process $proc -Title $title -Url $url -Keywords $keywords -Kind "browser"
    }
    return @{ Ok = $ok2; Hwnd = $hwnd; Title = $title; Youtube = $youtube; Matched = $matched }
}

function Test-JarvisMediaTitle {
    param([string]$Title)
    if ([string]::IsNullOrWhiteSpace($Title)) { return $false }
    # ASCII-only source (PS 5.1). Build RU tokens via codepoints.
    $ruYt = ([string]([char]0x044E) + [char]0x0442 + [char]0x0443 + [char]0x0431) # yutub
    $ruYm = ([string]([char]0x044F) + [char]0x043D + [char]0x0434 + [char]0x0435 + [char]0x043A + [char]0x0441) # yandeks
    $ruMu = ([string]([char]0x043C) + [char]0x0443 + [char]0x0437 + [char]0x044B + [char]0x043A) # muzyк stem
    return [bool]($Title -match "(?i)youtube|youtu\.be|$([regex]::Escape($ruYt))|music\.youtube|music\.yandex|yandex\.music|$([regex]::Escape($ruYm)).*$([regex]::Escape($ruMu))|vk\.com|vk\s*music|vk\s*$([regex]::Escape($ruMu))|netflix|twitch|rutube|vk\s*video|kinopoisk|ivi\.|ok\.ru/video|premier\.one")
}

function Get-JarvisMediaKind {
    param(
        [string]$Title,
        [string]$Url = "",
        [string]$Proc = ""
    )
    $t = "$Title"
    $u = "$Url"
    $p = "$Proc"
    $ruYt = ([string]([char]0x044E) + [char]0x0442 + [char]0x0443 + [char]0x0431)
    $ruYm = ([string]([char]0x044F) + [char]0x043D + [char]0x0434 + [char]0x0435 + [char]0x043A + [char]0x0441)
    $ruMu = ([string]([char]0x043C) + [char]0x0443 + [char]0x0437 + [char]0x044B + [char]0x043A)
    $ruVk = ([string]([char]0x0432) + [char]0x043A + [char]0x043E + [char]0x043D + [char]0x0442 + [char]0x0430 + [char]0x043A) # vkontakt stem
    $ruVid = ([string]([char]0x0432) + [char]0x0438 + [char]0x0434 + [char]0x0435 + [char]0x043E) # video
    if ($t -match "(?i)youtube|youtu\.be|music\.youtube|$([regex]::Escape($ruYt))" -or $u -match '(?i)youtube|youtu\.be') {
        return "youtube"
    }
    if ($t -match "(?i)music\.yandex|yandex\.music|$([regex]::Escape($ruYm))" -or $u -match '(?i)music\.yandex' -or $p -match '(?i)yandexmusic|music\.yandex') {
        return "yandex"
    }
    # VK Music / Video / Clips (web + vkvideo.ru). Not plain chat — Space pauses the player.
    if ($u -match '(?i)(?:vk\.(?:com|ru)|vkvideo\.ru)/(?:video|clip|clips|music|audio|live)|music\.vk\.com|vkvideo\.ru') {
        return "vk"
    }
    if ($t -match "(?i)vk\s*(?:music|video|clip)|vkvideo|vk\.com/(?:video|music|clip)") {
        return "vk"
    }
    if ($t -match "(?i)$([regex]::Escape($ruVk))" -and $t -match "(?i)$([regex]::Escape($ruVid))|$([regex]::Escape($ruMu))|music|audio|clip") {
        return "vk"
    }
    if ($t -match "(?i)vk\s*$([regex]::Escape($ruMu))" -or ($t -match '(?i)\bvk\b' -and $t -match "(?i)$([regex]::Escape($ruMu))|music|audio|video|clip")) {
        return "vk"
    }
    # Tab title often ends with "| VK" / em-dash VK while watching video.
    $emDash = [string]([char]0x2014)
    if ($t -match ('(?i)(?:\||' + [regex]::Escape($emDash) + '|-)\s*VK\s*$') -or $t -match '(?i)^VK\s*(?:Video|Music)?\b') {
        return "vk"
    }
    return "generic"
}

function Find-JarvisYandexMusicWindow {
    Initialize-JarvisLastTarget
    $ruYm = ([string]([char]0x042F) + [char]0x043D + [char]0x0434 + [char]0x0435 + [char]0x043A + [char]0x0441)
    $keys = [string[]]@("music.yandex", "yandex.music", "Yandex.Music", $ruYm)
    foreach ($allowIconic in @($false, $true)) {
        $h = [JarvisLastTarget]::FindByKeywords($keys, $allowIconic)
        if ($h -ne [IntPtr]::Zero) { return $h }
    }
    return [IntPtr]::Zero
}

function Find-JarvisVkMusicWindow {
    # VK Music + Video (same Space play/pause). Keep old name — callers already use it.
    Initialize-JarvisLastTarget
    $ruMu = ([string]([char]0x041C) + [char]0x0443 + [char]0x0437 + [char]0x044B + [char]0x043A + [char]0x0430) # Muzyka
    $ruVk = ([string]([char]0x0412) + [char]0x043A + [char]0x043E + [char]0x043D + [char]0x0442 + [char]0x0430 + [char]0x043A + [char]0x0442 + [char]0x0435) # VKontakte
    $emDash = [string]([char]0x2014)
    $keys = [string[]]@(
        "vk.com/video", "vk.com/music", "vk.com/clip", "music.vk", "vkvideo",
        "VK Video", "VK Music", ("VK " + $ruMu), $ruVk, " | VK", (" " + $emDash + " VK")
    )
    foreach ($allowIconic in @($false, $true)) {
        $h = [JarvisLastTarget]::FindByKeywords($keys, $allowIconic)
        if ($h -ne [IntPtr]::Zero) { return $h }
    }
    return [IntPtr]::Zero
}

function Find-JarvisYoutubeTab {
    Initialize-JarvisLastTarget
    $ru = ([string]([char]0x044E) + [char]0x0442 + [char]0x0443 + [char]0x0431)
    $keys = [string[]]@("youtube", "youtu", $ru)
    $h = [JarvisLastTarget]::FindByKeywords($keys, $false)
    if ($h -ne [IntPtr]::Zero) { return $h }
    return [JarvisLastTarget]::FindByKeywords($keys, $true)
}

function Get-JarvisMediaFocus {
    Initialize-JarvisLastTarget

    # 1) Foreground window (browser OR Yandex Music app).
    $fg = [JarvisLastTarget]::GetForegroundWindow()
    if ($fg -ne [IntPtr]::Zero -and -not [JarvisLastTarget]::IsJarvisHwnd($fg)) {
        $fgTitle = [JarvisLastTarget]::TitleOf($fg)
        $fgProc = [JarvisLastTarget]::ProcName($fg)
        $kind = Get-JarvisMediaKind -Title $fgTitle -Proc $fgProc
        $isBrowser = [JarvisLastTarget]::IsBrowserHwnd($fg)
        if ($isBrowser -or $kind -eq "yandex" -or $kind -eq "vk" -or (Test-JarvisMediaTitle $fgTitle)) {
            # Never force unknown media to youtube (VK Video used to get K instead of Space).
            if ($kind -eq "generic" -and $isBrowser) {
                $ruVkStem = ([string]([char]0x0432) + [char]0x043A + [char]0x043E + [char]0x043D + [char]0x0442 + [char]0x0430 + [char]0x043A)
                if ($fgTitle -match '(?i)youtube|youtu') { $kind = "youtube" }
                elseif ($fgTitle -match ('(?i)vk\.com|vkvideo|\bvk\b|' + [regex]::Escape($ruVkStem))) { $kind = "vk" }
            }
            Write-Host "JARVIS media-focus: foreground kind=$kind title='$fgTitle'"
            return @{
                Ok = $true; Hwnd = $fg; Title = $fgTitle; Youtube = ($kind -eq "youtube")
                Kind = $kind; Matched = $true; Foreground = $true; Proc = $fgProc
            }
        }
    }

    # 2) Last JARVIS media target (prefer over random YouTube tab when Jarvis stole focus).
    $savedEarly = Get-JarvisLastTarget
    if ($null -ne $savedEarly) {
        $earlyUrl = [string]$savedEarly.url
        $earlyKind = Get-JarvisMediaKind -Title ([string]$savedEarly.title) -Url $earlyUrl
        if ($earlyKind -eq "generic" -and ($earlyUrl -match '(?i)youtube|youtu\.be')) { $earlyKind = "youtube" }
        if ($earlyKind -eq "generic" -and ($earlyUrl -match '(?i)vk\.(?:com|ru)|vkvideo')) { $earlyKind = "vk" }
        if ($earlyKind -ne "generic") {
            $earlyHwnd = [IntPtr]::Zero
            try { $earlyHwnd = [IntPtr]([int64]$savedEarly.hwnd) } catch { $earlyHwnd = [IntPtr]::Zero }
            if ($earlyHwnd -eq [IntPtr]::Zero -or -not [JarvisLastTarget]::IsWindow($earlyHwnd)) {
                $earlyHwnd = Resolve-JarvisControlHwnd
            }
            if ($earlyHwnd -ne [IntPtr]::Zero) {
                $ok = [JarvisLastTarget]::WaitForeground($earlyHwnd, 16)
                $title = [JarvisLastTarget]::TitleOf($earlyHwnd)
                $kind = Get-JarvisMediaKind -Title $title -Url $earlyUrl
                if ($kind -eq "generic") { $kind = $earlyKind }
                if ($ok) {
                    Write-Host "JARVIS media-focus: last-target-early kind=$kind title='$title'"
                    return @{ Ok = $true; Hwnd = $earlyHwnd; Title = $title; Youtube = ($kind -eq "youtube"); Kind = $kind; Matched = $true }
                }
            }
        }
    }

    # 3) YouTube tab
    $ytHwnd = Find-JarvisYoutubeTab
    if ($ytHwnd -ne [IntPtr]::Zero) {
        $ok = [JarvisLastTarget]::WaitForeground($ytHwnd, 16)
        $title = [JarvisLastTarget]::TitleOf($ytHwnd)
        Write-Host "JARVIS media-focus: YouTube tab '$title'"
        return @{ Ok = $ok; Hwnd = $ytHwnd; Title = $title; Youtube = $true; Kind = "youtube"; Matched = $true }
    }

    # 4) Yandex Music (site or desktop app)
    $ym = Find-JarvisYandexMusicWindow
    if ($ym -ne [IntPtr]::Zero) {
        $ok = [JarvisLastTarget]::WaitForeground($ym, 16)
        $title = [JarvisLastTarget]::TitleOf($ym)
        Write-Host "JARVIS media-focus: Yandex Music '$title'"
        return @{ Ok = $ok; Hwnd = $ym; Title = $title; Youtube = $false; Kind = "yandex"; Matched = $true }
    }

    # 5) VK Music / Video
    $vk = Find-JarvisVkMusicWindow
    if ($vk -ne [IntPtr]::Zero) {
        $ok = [JarvisLastTarget]::WaitForeground($vk, 16)
        $title = [JarvisLastTarget]::TitleOf($vk)
        Write-Host "JARVIS media-focus: VK '$title'"
        return @{ Ok = $ok; Hwnd = $vk; Title = $title; Youtube = $false; Kind = "vk"; Matched = $true }
    }

    # 6) Last JARVIS-opened browser tab (any)
    $hwnd = Resolve-JarvisControlHwnd
    if ($hwnd -ne [IntPtr]::Zero) {
        $ok = [JarvisLastTarget]::WaitForeground($hwnd, 14)
        $title = [JarvisLastTarget]::TitleOf($hwnd)
        $saved = Get-JarvisLastTarget
        $url = if ($null -ne $saved) { [string]$saved.url } else { "" }
        $sameHwnd = $false
        if ($null -ne $saved) {
            try { $sameHwnd = ([IntPtr]([int64]$saved.hwnd) -eq $hwnd) } catch { $sameHwnd = $false }
        }
        $kind = Get-JarvisMediaKind -Title $title -Url $(if ($sameHwnd) { $url } else { "" })
        if ($kind -eq "generic" -and $sameHwnd -and ($url -match '(?i)youtube|youtu\.be')) { $kind = "youtube" }
        if ($kind -eq "generic" -and $sameHwnd -and ($url -match '(?i)vk\.(?:com|ru)|vkvideo')) { $kind = "vk" }
        if ($ok) {
            Write-Host "JARVIS media-focus: last-target kind=$kind title='$title'"
            return @{ Ok = $true; Hwnd = $hwnd; Title = $title; Youtube = ($kind -eq "youtube"); Kind = $kind; Matched = $true }
        }
    }

    # 6) Other video sites by title.
    foreach ($kw in @("netflix", "twitch", "rutube", "kinopoisk", "ivi")) {
        $h = [JarvisLastTarget]::FindByKeywords([string[]]@($kw), $true)
        if ($h -ne [IntPtr]::Zero) {
            $ok = [JarvisLastTarget]::WaitForeground($h, 12)
            $title = [JarvisLastTarget]::TitleOf($h)
            return @{ Ok = $ok; Hwnd = $h; Title = $title; Youtube = $false; Kind = "generic"; Matched = $true }
        }
    }

    return @{ Ok = $false; Hwnd = [IntPtr]::Zero; Title = ""; Youtube = $false; Kind = "generic"; Matched = $false }
}

function Invoke-JarvisVkMedia {
    param(
        [IntPtr]$Hwnd,
        [string]$Action,
        [bool]$Youtube = $false,
        [string]$Kind = ""
    )
    if ($Hwnd -eq [IntPtr]::Zero) { return $false }
    [void][JarvisLastTarget]::WaitForeground($Hwnd, 18)
    # VK/Yandex need a beat after focus or Space lands in the wrong place.
    $waitMs = if ($Kind -eq "vk" -or $Kind -eq "yandex") { 140 } else { 90 }
    Start-Sleep -Milliseconds $waitMs

    if ([string]::IsNullOrWhiteSpace($Kind)) {
        $Kind = if ($Youtube) { "youtube" } else { "generic" }
    }
    $Kind = $Kind.ToLowerInvariant()

    # Physical VK codes - layout-independent (SendKeys breaks on Russian keyboard).
    # Never click the video player: click would toggle play, then keys toggle again.
    if ($Kind -eq "youtube") {
        switch ($Action) {
            "play_pause" { [JarvisLastTarget]::Tap([JarvisLastTarget]::VK_K); return $true }
            "stop"       { [JarvisLastTarget]::Tap([JarvisLastTarget]::VK_K); return $true }
            "next"       { [JarvisLastTarget]::Chord([JarvisLastTarget]::VK_SHIFT, [JarvisLastTarget]::VK_N); return $true }
            "prev"       { [JarvisLastTarget]::Chord([JarvisLastTarget]::VK_SHIFT, [JarvisLastTarget]::VK_P); return $true }
        }
    }

    # Yandex Music (web + desktop when focused): L/J next, H/K prev (docs / community).
    # Also Space for play/pause (official: Space repeats last player action).
    if ($Kind -eq "yandex") {
        switch ($Action) {
            "play_pause" { [JarvisLastTarget]::Tap([JarvisLastTarget]::VK_SPACE); return $true }
            "stop"       { [JarvisLastTarget]::Tap([JarvisLastTarget]::VK_SPACE); return $true }
            "next"       { [JarvisLastTarget]::Tap([JarvisLastTarget]::VK_L); return $true }
            "prev"       { [JarvisLastTarget]::Tap([JarvisLastTarget]::VK_H); return $true }
        }
    }

    # VK Music + Video (web): Space play/pause; Ctrl+Arrows for tracks.
    if ($Kind -eq "vk") {
        switch ($Action) {
            "play_pause" { [JarvisLastTarget]::Tap([JarvisLastTarget]::VK_SPACE); return $true }
            "stop"       { [JarvisLastTarget]::Tap([JarvisLastTarget]::VK_SPACE); return $true }
            "next"       { [JarvisLastTarget]::Chord([JarvisLastTarget]::VK_CONTROL, [JarvisLastTarget]::VK_RIGHT); return $true }
            "prev"       { [JarvisLastTarget]::Chord([JarvisLastTarget]::VK_CONTROL, [JarvisLastTarget]::VK_LEFT); return $true }
        }
    }

    if ($Action -eq "play_pause" -or $Action -eq "stop") {
        [JarvisLastTarget]::Tap([JarvisLastTarget]::VK_SPACE)
        return $true
    }
    return $false
}
