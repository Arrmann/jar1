param(
    [Parameter(Position = 0)]
    [ValidateSet("min", "max", "expand", "video", "video_exit")]
    [string]$Mode = "max",

    # Optional: force a specific HWND (decimal). Used by tests / diagnostics.
    [long]$ForceHwnd = 0
)

# min/max/expand = OS window size on the window's own monitor.
# video = find YouTube browser → OS maximize (no player F — F toggles and looks like collapse).
# video_exit = leave player FS if any, then OS-minimize the YouTube browser.
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_jarvis-last-target.ps1")
Initialize-JarvisLastTarget

# Per-monitor DPI so GetWindowRect / SetCursorPos match real pixels on other PCs.
try {
    Add-Type -Namespace JarvisDpi -Name Aware -MemberDefinition @"
using System;
using System.Runtime.InteropServices;
public static class JarvisDpiAware {
  [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] static extern IntPtr SetProcessDpiAwarenessContext(IntPtr value);
  public static void Enable() {
    try { SetProcessDpiAwarenessContext((IntPtr)(-4)); } catch {}
    try { SetProcessDPIAware(); } catch {}
  }
}
"@ -ErrorAction SilentlyContinue
    [JarvisDpi.Aware]::Enable()
} catch {}

$WM_SYSCOMMAND = 0x0112
$SC_MAXIMIZE = 0xF030
$SC_MINIMIZE = 0xF020
$SW_MINIMIZE = 6

if (-not ("JarvisWinSizeEx" -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class JarvisWinSizeEx {
  public const uint GA_ROOT = 2;
  public const int SW_RESTORE = 9;
  public const int SW_SHOW = 5;
  public const int SW_SHOWMAXIMIZED = 3;
  public const int SW_MINIMIZE = 6;
  public const uint SPI_GETWORKAREA = 0x0030;
  public const uint SWP_NOZORDER = 0x0004;
  public const uint SWP_SHOWWINDOW = 0x0040;
  public const uint SWP_FRAMECHANGED = 0x0020;
  public const uint WM_SYSCOMMAND = 0x0112;
  public const int SC_MAXIMIZE = 0xF030;
  public const uint SMTO_ABORTIFHUNG = 0x0002;
  public const uint MONITOR_DEFAULTTONEAREST = 2;
  public const int SM_XVIRTUALSCREEN = 76;
  public const int SM_YVIRTUALSCREEN = 77;
  public const int SM_CXVIRTUALSCREEN = 78;
  public const int SM_CYVIRTUALSCREEN = 79;

  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
  [DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam, uint fuFlags, uint uTimeout, out IntPtr lpdwResult);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr hwnd, uint gaFlags);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int X, int Y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool SystemParametersInfo(uint uiAction, uint uiParam, ref RECT pvParam, uint fWinIni);
  [DllImport("user32.dll")] public static extern bool GetWindowPlacement(IntPtr hWnd, ref WINDOWPLACEMENT lpwndpl);
  [DllImport("user32.dll")] public static extern bool SetWindowPlacement(IntPtr hWnd, ref WINDOWPLACEMENT lpwndpl);
  [DllImport("user32.dll")] public static extern IntPtr MonitorFromWindow(IntPtr hwnd, uint dwFlags);
  [DllImport("user32.dll")] public static extern IntPtr MonitorFromPoint(POINT pt, uint dwFlags);
  [DllImport("user32.dll")] public static extern bool GetMonitorInfo(IntPtr hMonitor, ref MONITORINFO lpmi);
  [DllImport("user32.dll")] public static extern int GetSystemMetrics(int nIndex);

  [StructLayout(LayoutKind.Sequential)]
  public struct POINT { public int X, Y; }
  [StructLayout(LayoutKind.Sequential)]
  public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)]
  public struct WINDOWPLACEMENT {
    public int length;
    public int flags;
    public int showCmd;
    public POINT ptMinPosition;
    public POINT ptMaxPosition;
    public RECT rcNormalPosition;
  }
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
  public struct MONITORINFO {
    public int cbSize;
    public RECT rcMonitor;
    public RECT rcWork;
    public uint dwFlags;
  }

  public static IntPtr RootOf(IntPtr hWnd) {
    if (hWnd == IntPtr.Zero || !IsWindow(hWnd)) return IntPtr.Zero;
    IntPtr root = GetAncestor(hWnd, GA_ROOT);
    if (root != IntPtr.Zero && IsWindow(root)) return root;
    return hWnd;
  }

  public static RECT WorkAreaForWindow(IntPtr hWnd) {
    hWnd = RootOf(hWnd);
    IntPtr mon = MonitorFromWindow(hWnd, MONITOR_DEFAULTTONEAREST);
    MONITORINFO mi = new MONITORINFO();
    mi.cbSize = Marshal.SizeOf(typeof(MONITORINFO));
    if (mon != IntPtr.Zero && GetMonitorInfo(mon, ref mi)) return mi.rcWork;
    RECT wa = new RECT();
    SystemParametersInfo(SPI_GETWORKAREA, 0, ref wa, 0);
    return wa;
  }

  public static RECT VirtualScreen() {
    RECT v = new RECT();
    v.Left = GetSystemMetrics(SM_XVIRTUALSCREEN);
    v.Top = GetSystemMetrics(SM_YVIRTUALSCREEN);
    v.Right = v.Left + GetSystemMetrics(SM_CXVIRTUALSCREEN);
    v.Bottom = v.Top + GetSystemMetrics(SM_CYVIRTUALSCREEN);
    if (v.Right <= v.Left || v.Bottom <= v.Top) {
      v.Left = 0; v.Top = 0; v.Right = 1920; v.Bottom = 1080;
    }
    return v;
  }

  public static bool CoversWorkArea(IntPtr hWnd) {
    RECT wr, wa;
    if (!GetWindowRect(hWnd, out wr)) return false;
    wa = WorkAreaForWindow(hWnd);
    int ww = wr.Right - wr.Left;
    int wh = wr.Bottom - wr.Top;
    int aw = wa.Right - wa.Left;
    int ah = wa.Bottom - wa.Top;
    if (aw < 200 || ah < 200) return IsZoomed(hWnd);
    return ww >= aw - 24 && wh >= ah - 24
        && wr.Left <= wa.Left + 16
        && wr.Top <= wa.Top + 16;
  }

  public static bool LooksMaximized(IntPtr hWnd) {
    return IsZoomed(hWnd) || CoversWorkArea(hWnd);
  }

  /// Move window onto a visible monitor if it sits mostly off the virtual desktop.
  public static bool EnsureOnScreen(IntPtr hWnd) {
    hWnd = RootOf(hWnd);
    if (hWnd == IntPtr.Zero || !IsWindow(hWnd)) return false;
    RECT wr;
    if (!GetWindowRect(hWnd, out wr)) return false;
    int ww = wr.Right - wr.Left;
    int wh = wr.Bottom - wr.Top;
    if (ww < 80) ww = 900;
    if (wh < 60) wh = 600;

    RECT vs = VirtualScreen();
    int cx = wr.Left + ww / 2;
    int cy = wr.Top + wh / 2;
    bool centerVisible = cx >= vs.Left && cx < vs.Right && cy >= vs.Top && cy < vs.Bottom;
    int interL = Math.Max(wr.Left, vs.Left);
    int interT = Math.Max(wr.Top, vs.Top);
    int interR = Math.Min(wr.Right, vs.Right);
    int interB = Math.Min(wr.Bottom, vs.Bottom);
    int interArea = Math.Max(0, interR - interL) * Math.Max(0, interB - interT);
    int winArea = Math.Max(1, ww * wh);
    bool mostlyVisible = interArea * 100 / winArea >= 35;
    if (centerVisible && mostlyVisible) return true;

    RECT wa = WorkAreaForWindow(hWnd);
    // If hwnd was off every monitor, WorkAreaForWindow still returns nearest; also try primary.
    if (wa.Right - wa.Left < 200) {
      SystemParametersInfo(SPI_GETWORKAREA, 0, ref wa, 0);
    }
    int pad = 24;
    int nx = wa.Left + pad;
    int ny = wa.Top + pad;
    int nw = Math.Min(ww, (wa.Right - wa.Left) - 2 * pad);
    int nh = Math.Min(wh, (wa.Bottom - wa.Top) - 2 * pad);
    if (nw < 640) nw = Math.Min(1100, (wa.Right - wa.Left) - 2 * pad);
    if (nh < 400) nh = Math.Min(700, (wa.Bottom - wa.Top) - 2 * pad);
    if (IsIconic(hWnd) || IsZoomed(hWnd)) ShowWindow(hWnd, SW_RESTORE);
    System.Threading.Thread.Sleep(30);
    SetWindowPos(hWnd, IntPtr.Zero, nx, ny, nw, nh, SWP_NOZORDER | SWP_SHOWWINDOW | SWP_FRAMECHANGED);
    ShowWindow(hWnd, SW_SHOW);
    return true;
  }

  public static bool ForceMaximize(IntPtr hWnd) {
    hWnd = RootOf(hWnd);
    if (hWnd == IntPtr.Zero || !IsWindow(hWnd)) return false;

    EnsureOnScreen(hWnd);

    if (IsIconic(hWnd)) {
      ShowWindow(hWnd, SW_RESTORE);
      System.Threading.Thread.Sleep(50);
    }

    if (LooksMaximized(hWnd)) return true;

    ShowWindow(hWnd, SW_RESTORE);
    System.Threading.Thread.Sleep(30);

    ShowWindow(hWnd, SW_SHOWMAXIMIZED);
    System.Threading.Thread.Sleep(50);
    if (LooksMaximized(hWnd)) return true;

    WINDOWPLACEMENT wp = new WINDOWPLACEMENT();
    wp.length = Marshal.SizeOf(typeof(WINDOWPLACEMENT));
    if (GetWindowPlacement(hWnd, ref wp)) {
      wp.showCmd = SW_SHOWMAXIMIZED;
      wp.flags = 0;
      SetWindowPlacement(hWnd, ref wp);
      System.Threading.Thread.Sleep(50);
      if (LooksMaximized(hWnd)) return true;
    }

    PostMessage(hWnd, WM_SYSCOMMAND, (IntPtr)SC_MAXIMIZE, IntPtr.Zero);
    System.Threading.Thread.Sleep(50);
    if (LooksMaximized(hWnd)) return true;

    IntPtr ignored;
    SendMessageTimeout(hWnd, WM_SYSCOMMAND, (IntPtr)SC_MAXIMIZE, IntPtr.Zero, SMTO_ABORTIFHUNG, 200, out ignored);
    System.Threading.Thread.Sleep(40);
    if (LooksMaximized(hWnd)) return true;

    ShowWindowAsync(hWnd, SW_SHOWMAXIMIZED);
    System.Threading.Thread.Sleep(60);
    if (LooksMaximized(hWnd)) return true;

    // Fill THIS window's monitor work area - never primary-only SPI.
    RECT wa = WorkAreaForWindow(hWnd);
    int w = wa.Right - wa.Left;
    int h = wa.Bottom - wa.Top;
    if (w >= 200 && h >= 120) {
      if (IsZoomed(hWnd) || IsIconic(hWnd)) ShowWindow(hWnd, SW_RESTORE);
      System.Threading.Thread.Sleep(20);
      SetWindowPos(hWnd, IntPtr.Zero, wa.Left, wa.Top, w, h, SWP_NOZORDER | SWP_SHOWWINDOW | SWP_FRAMECHANGED);
      System.Threading.Thread.Sleep(30);
      ShowWindow(hWnd, SW_SHOWMAXIMIZED);
      System.Threading.Thread.Sleep(40);
      if (LooksMaximized(hWnd)) return true;
      if (CoversWorkArea(hWnd)) return true;
    }
    return LooksMaximized(hWnd);
  }
}
"@
}

function Test-IsJarvisOrShell([IntPtr]$hwnd) {
    if ($hwnd -eq [IntPtr]::Zero) { return $true }
    if ([JarvisLastTarget]::IsJarvisHwnd($hwnd)) { return $true }
    $cls = New-Object Text.StringBuilder 256
    [void][JarvisLastTarget]::GetClassName($hwnd, $cls, $cls.Capacity)
    $c = $cls.ToString()
    if ($c -eq "Progman" -or $c -eq "WorkerW" -or $c -eq "Shell_TrayWnd" -or $c -eq "Shell_SecondaryTrayWnd") { return $true }
    return $false
}

function Get-PreferredBeforeYield {
    $saved = Get-JarvisLastTarget
    if ($null -ne $saved) {
        try {
            $n = [int64]$saved.hwnd
            if ($n -ne 0) {
                $h = [IntPtr]$n
                if ([JarvisLastTarget]::IsWindow($h) -and -not (Test-IsJarvisOrShell $h)) {
                    return [JarvisWinSizeEx]::RootOf($h)
                }
            }
        } catch {}
    }
    $br = [JarvisLastTarget]::FindTopBrowser($true)
    if ($br -ne [IntPtr]::Zero) { return [JarvisWinSizeEx]::RootOf($br) }
    $ex = [JarvisLastTarget]::FindTopExplorerFolder($true)
    if ($ex -ne [IntPtr]::Zero) { return $ex }
    return [IntPtr]::Zero
}

function Get-ActiveTarget {
    if ($ForceHwnd -ne 0) {
        $forced = [IntPtr]$ForceHwnd
        if ([JarvisLastTarget]::IsWindow($forced)) {
            Write-Host "JARVIS window-size: target=forced"
            return [JarvisWinSizeEx]::RootOf($forced)
        }
    }

    $preferred = Get-PreferredBeforeYield

    $fg = [JarvisLastTarget]::GetForegroundWindow()
    $wasJarvis = ($fg -ne [IntPtr]::Zero -and [JarvisLastTarget]::IsJarvisHwnd($fg))
    if ($wasJarvis) {
        [JarvisLastTarget]::YieldJarvis()
        Start-Sleep -Milliseconds 80
        $fg = [JarvisLastTarget]::GetForegroundWindow()
    }

    if ($fg -ne [IntPtr]::Zero -and -not (Test-IsJarvisOrShell $fg)) {
        $root = [JarvisWinSizeEx]::RootOf($fg)
        if ($wasJarvis -and $preferred -ne [IntPtr]::Zero) {
            $fgBrowser = [JarvisLastTarget]::IsBrowserHwnd($root)
            $prefBrowser = [JarvisLastTarget]::IsBrowserHwnd($preferred)
            if ($prefBrowser -and -not $fgBrowser) {
                Write-Host "JARVIS window-size: target=preferred-browser (FG was non-browser after yield)"
                return $preferred
            }
        }
        Write-Host "JARVIS window-size: target=foreground"
        return $root
    }

    if ($preferred -ne [IntPtr]::Zero) {
        Write-Host "JARVIS window-size: target=preferred"
        return $preferred
    }

    $br = [JarvisLastTarget]::FindTopBrowser($true)
    if ($br -ne [IntPtr]::Zero) {
        Write-Host "JARVIS window-size: target=top-browser"
        return [JarvisWinSizeEx]::RootOf($br)
    }
    $ex = [JarvisLastTarget]::FindTopExplorerFolder($true)
    if ($ex -ne [IntPtr]::Zero) {
        Write-Host "JARVIS window-size: target=top-explorer"
        return $ex
    }
    return [IntPtr]::Zero
}

function Invoke-Maximize([IntPtr]$hwnd) {
    $hwnd = [JarvisWinSizeEx]::RootOf($hwnd)
    Write-Host ("JARVIS window-size: maximize hwnd={0} zoomed={1}" -f [int64]$hwnd, [JarvisWinSizeEx]::IsZoomed($hwnd))

    [void][JarvisLastTarget]::FocusWindow($hwnd)
    Start-Sleep -Milliseconds 40
    [void][JarvisWinSizeEx]::EnsureOnScreen($hwnd)

    if ([JarvisWinSizeEx]::LooksMaximized($hwnd)) {
        Write-Host "JARVIS window-size: already maximized"
        return $true
    }

    if ([JarvisWinSizeEx]::ForceMaximize($hwnd)) {
        Write-Host "JARVIS window-size: maximized OK (own monitor)"
        return $true
    }

    # Win+Up only if we still own foreground - otherwise it maximizes the wrong app.
    $fg = [JarvisLastTarget]::GetForegroundWindow()
    if ($fg -eq $hwnd -or [JarvisWinSizeEx]::RootOf($fg) -eq $hwnd) {
        [JarvisLastTarget]::Chord([byte]0x5B, [byte]0x26)
        Start-Sleep -Milliseconds 100
        if ([JarvisWinSizeEx]::LooksMaximized($hwnd)) {
            Write-Host "JARVIS window-size: maximized via Win+Up"
            return $true
        }
    }

    Write-Host "JARVIS window-size: maximize FAILED"
    return $false
}

function Invoke-Minimize([IntPtr]$hwnd) {
    $hwnd = [JarvisWinSizeEx]::RootOf($hwnd)
    [void][JarvisLastTarget]::FocusWindow($hwnd)
    [void][JarvisWinSizeEx]::ShowWindow($hwnd, $SW_MINIMIZE)
    Start-Sleep -Milliseconds 40
    if ([JarvisWinSizeEx]::IsIconic($hwnd)) {
        Write-Host "JARVIS window-size: minimized"
        return $true
    }
    [void][JarvisWinSizeEx]::PostMessage($hwnd, $WM_SYSCOMMAND, [IntPtr]$SC_MINIMIZE, [IntPtr]::Zero)
    Write-Host "JARVIS window-size: minimize via SC_MINIMIZE"
    return $true
}

function Test-TitleLooksYoutube([string]$title) {
    if ([string]::IsNullOrWhiteSpace($title)) { return $false }
    # ASCII-only source; build RU "yutub" via codepoints (PS 5.1 + UTF-8 without BOM).
    $ru = ([string]([char]0x044E) + [char]0x0442 + [char]0x0443 + [char]0x0431) # yutub
    $ru2 = $ru + ([string]([char]0x044C)) # soft sign variant sometimes heard
    return [bool]($title -match "(?i)youtube|youtu\.be|$([regex]::Escape($ru))|$([regex]::Escape($ru2))")
}

function Test-UrlLooksYoutube([string]$url) {
    if ([string]::IsNullOrWhiteSpace($url)) { return $false }
    return [bool]($url -match '(?i)youtube\.com|youtu\.be')
}

function Test-IsYoutubeWindow([IntPtr]$hwnd) {
    if ($hwnd -eq [IntPtr]::Zero) { return $false }
    $title = [JarvisLastTarget]::TitleOf($hwnd)
    if (Test-TitleLooksYoutube $title) { return $true }
    # Stale last-target URL must match THIS hwnd - never invent YouTube for Gmail etc.
    $saved = Get-JarvisLastTarget
    if ($null -eq $saved) { return $false }
    try {
        $savedHwnd = [IntPtr]([int64]$saved.hwnd)
    } catch {
        return $false
    }
    if ($savedHwnd -eq [IntPtr]::Zero) { return $false }
    if ([JarvisWinSizeEx]::RootOf($savedHwnd) -ne [JarvisWinSizeEx]::RootOf($hwnd)) { return $false }
    return (Test-UrlLooksYoutube ([string]$saved.url))
}

function Test-LooksLikeWatchPage([IntPtr]$hwnd) {
    $title = [JarvisLastTarget]::TitleOf($hwnd)
    # Studio / Music / channel home are not the HTML5 watch player — OS max only.
    if ($title -match '(?i)youtube\s*studio|studio\.youtube|youtube\s*music|music\.youtube') {
        return $false
    }
    if ($title -match '(?i)/watch|youtu\.be/') { return $true }
    # "Video Name - YouTube" is longer than bare "YouTube" / "YouTube - Home"
    if ((Test-TitleLooksYoutube $title) -and $title.Length -ge 18 -and $title -notmatch '(?i)^youtube\b') {
        return $true
    }
    $saved = Get-JarvisLastTarget
    if ($null -ne $saved) {
        try {
            $savedHwnd = [IntPtr]([int64]$saved.hwnd)
            if ([JarvisWinSizeEx]::RootOf($savedHwnd) -eq [JarvisWinSizeEx]::RootOf($hwnd)) {
                if ([string]$saved.url -match '(?i)youtube\.com/watch|youtu\.be/') { return $true }
            }
        } catch {}
    }
    return $false
}

function Test-TitleLooksOtherSite([string]$title) {
    if ([string]::IsNullOrWhiteSpace($title)) { return $false }
    if (Test-TitleLooksYoutube $title) { return $false }
    # Visible title clearly not YouTube — never maximize this HWND from a stale URL.
    return [bool]($title -match '(?i)gmail|mail\.google|google\s*search|docs\.google|github|notion|telegram|discord|twitch|netflix|spotify|vk\.com|mail\.ru|yandex\.(?:ru|com)|bing\.com|chatgpt|openai')
}

function Resolve-YoutubeHwndOnce {
    # Prefer last JARVIS-opened YouTube window when still valid.
    $saved = Get-JarvisLastTarget
    $urlOkSaved = $false
    if ($null -ne $saved) {
        $urlOkSaved = Test-UrlLooksYoutube ([string]$saved.url)
        try {
            $n = [int64]$saved.hwnd
            if ($n -ne 0) {
                $h = [JarvisWinSizeEx]::RootOf([IntPtr]$n)
                if ($h -ne [IntPtr]::Zero -and [JarvisLastTarget]::IsWindow($h) -and [JarvisLastTarget]::IsBrowserHwnd($h)) {
                    $t = [JarvisLastTarget]::TitleOf($h)
                    $titleOk = Test-TitleLooksYoutube $t
                    $loading = ($t.Length -lt 3) -or ($t -match '(?i)new tab|about:blank|untitled|без названия|loading|новая вкладка|загрузка')
                    # URL from open_youtube is trusted while the tab title is still loading
                    # or still YouTube — never if the title is clearly another site.
                    if ($titleOk -or ($urlOkSaved -and ($loading -or -not (Test-TitleLooksOtherSite $t)))) {
                        Write-Host "JARVIS window-size: youtube=last-target title=$t"
                        return $h
                    }
                }
            }
        } catch {}
    }

    $yt = Find-JarvisYoutubeTab
    if ($yt -ne [IntPtr]::Zero) {
        Write-Host "JARVIS window-size: youtube=title-scan"
        return [JarvisWinSizeEx]::RootOf($yt)
    }

    # open_youtube race: last-target URL is YouTube but hwnd not registered yet —
    # accept top browser only while title is empty/loading/YouTube (never Gmail etc.).
    if ($urlOkSaved) {
        $top = [JarvisLastTarget]::FindTopBrowser($true)
        if ($top -ne [IntPtr]::Zero -and -not [JarvisLastTarget]::IsJarvisHwnd($top)) {
            $t = [JarvisLastTarget]::TitleOf($top)
            $loading = ($t.Length -lt 3) -or ($t -match '(?i)new tab|about:blank|untitled|без названия|loading|новая вкладка|загрузка')
            if ((Test-TitleLooksYoutube $t) -or $loading) {
                Write-Host "JARVIS window-size: youtube=top-browser-open-race title=$t"
                return [JarvisWinSizeEx]::RootOf($top)
            }
        }
    }

    $mf = Get-JarvisMediaFocus
    if ($mf.Ok -and $mf.Hwnd -ne [IntPtr]::Zero) {
        $h = [JarvisWinSizeEx]::RootOf([IntPtr]$mf.Hwnd)
        if (Test-IsYoutubeWindow $h) {
            Write-Host "JARVIS window-size: youtube=media-focus"
            return $h
        }
    }
    return [IntPtr]::Zero
}

function Resolve-YoutubeHwnd {
    # Retries: «открой ютуб» + «разверни ютуб» back-to-back on slow PCs —
    # last-target / title often lag behind the new tab (~4s cold Chrome/Edge).
    for ($i = 0; $i -lt 20; $i++) {
        $h = Resolve-YoutubeHwndOnce
        if ($h -ne [IntPtr]::Zero) { return $h }
        Start-Sleep -Milliseconds 200
    }
    return [IntPtr]::Zero
}

function Invoke-YoutubeExpand([IntPtr]$hwnd) {
    $hwnd = [JarvisWinSizeEx]::RootOf($hwnd)
    $title = [JarvisLastTarget]::TitleOf($hwnd)
    Write-Host "JARVIS window-size: youtube-expand title=$title"

    [void][JarvisWinSizeEx]::EnsureOnScreen($hwnd)
    [void][JarvisLastTarget]::WaitForegroundExact($hwnd, 24)
    Start-Sleep -Milliseconds 40

    # OS-maximize first (no-op if already zoomed - used to make expand feel dead).
    $ok = Invoke-Maximize $hwnd
    if (-not $ok) {
        Write-Host "JARVIS window-size: youtube maximize FAILED"
        return $false
    }

    # Player fullscreen (F). F alone toggles - Esc then F always enters FS.
    # Skip on Studio/Music/home: F does nothing useful there.
    $watch = Test-LooksLikeWatchPage $hwnd
    if ($watch) {
        $fgOk = [JarvisLastTarget]::WaitForegroundExact($hwnd, 16)
        if ($fgOk) {
            [JarvisLastTarget]::Tap([JarvisLastTarget]::VK_ESCAPE)
            Start-Sleep -Milliseconds 70
            [JarvisLastTarget]::Tap([JarvisLastTarget]::VK_F)
            Start-Sleep -Milliseconds 80
            Write-Host "JARVIS window-size: youtube player fullscreen (Esc+F)"
        } else {
            Write-Host "JARVIS window-size: skip player F (no foreground)"
        }
    } else {
        Write-Host "JARVIS window-size: youtube OS-maximized (not a watch page - no player F)"
    }
    return $true
}

function Invoke-YoutubeCollapse([IntPtr]$hwnd) {
    $hwnd = [JarvisWinSizeEx]::RootOf($hwnd)
    $title = [JarvisLastTarget]::TitleOf($hwnd)
    Write-Host "JARVIS window-size: youtube-collapse title=$title"

    [void][JarvisWinSizeEx]::EnsureOnScreen($hwnd)
    $fgOk = [JarvisLastTarget]::WaitForegroundExact($hwnd, 24)
    if (-not $fgOk) {
        Write-Host "JARVIS window-size: youtube collapse FAILED (no foreground)"
        return $false
    }

    # Exit player/theater fullscreen only - do NOT OS-minimize the browser.
    # Pair: «разверни ютуб» = Esc+F enter FS, «сверни ютуб» = Esc leave FS.
    [JarvisLastTarget]::Tap([JarvisLastTarget]::VK_ESCAPE)
    Start-Sleep -Milliseconds 70
    [JarvisLastTarget]::Tap([JarvisLastTarget]::VK_ESCAPE)
    Start-Sleep -Milliseconds 40
    Write-Host "JARVIS window-size: youtube player fullscreen exited (Esc, window stays)"
    return $true
}

# --- main ---
if ($Mode -eq "video" -or $Mode -eq "video_exit") {
    $yt = Resolve-YoutubeHwnd
    if ($yt -eq [IntPtr]::Zero) {
        # Marker kept for tools/test-youtube-expand.ps1 — never maximize a random window.
        Write-Host "JARVIS window-size: $Mode - no YouTube window (refuse wrong-window maximize)"
        exit 3
    }
    $ok = if ($Mode -eq "video_exit") {
        Invoke-YoutubeCollapse $yt
    } else {
        Invoke-YoutubeExpand $yt
    }
    if ($ok) { exit 0 }
    exit 1
}

$hwnd = Get-ActiveTarget
if ($hwnd -eq [IntPtr]::Zero) {
    Write-Host "JARVIS window-size: no target window"
    exit 2
}

$proc = [JarvisLastTarget]::ProcName($hwnd)
$title = [JarvisLastTarget]::TitleOf($hwnd)
Write-Host "JARVIS window-size: mode=$Mode proc=$proc title=$title"

if ($Mode -eq "min") {
    [void](Invoke-Minimize $hwnd)
    exit 0
}

if (Invoke-Maximize $hwnd) { exit 0 }
exit 1
