# True minimize-all.
# Shell.Application.MinimizeAll / Win+D only hides windows (Show Desktop).
# The next focus change, or a second call, restores them. SW_MINIMIZE (6)
# also activates the next window, which pops already-minimized windows back.
# This script force-minimizes each real top-level window and does not toggle.
param(
    [string]$OnlyProcess = "",
    [string]$OnlyHwnds = "",
    [switch]$ListOnly
)

$ErrorActionPreference = "SilentlyContinue"
$asciiTemp = "C:\ProgramData\JARVIS\pscache"
try {
    New-Item -ItemType Directory -Force -Path $asciiTemp | Out-Null
    $env:TEMP = $asciiTemp
    $env:TMP = $asciiTemp
} catch {}

if (-not ("JarvisMinAllEx" -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Runtime.InteropServices;

public static class JarvisMinAllEx {
  public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);

  public const int SW_SHOWMINNOACTIVE = 7;
  public const int SW_FORCEMINIMIZE = 11;
  public const int SW_SHOWMINIMIZED = 2;
  public const int GWL_EXSTYLE = -20;
  public const int WS_EX_TOOLWINDOW = 0x00000080;
  public const int WS_EX_APPWINDOW = 0x00040000;
  public const int DWMWA_CLOAKED = 14;
  public const uint WM_SYSCOMMAND = 0x0112;
  public const int SC_MINIMIZE = 0xF020;
  public const int WPF_ASYNCWINDOWPLACEMENT = 0x0004;

  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc lpEnumFunc, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, StringBuilder lp, int nMax);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lp, int nMax);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
  [DllImport("user32.dll", EntryPoint = "GetWindowLongW")] public static extern int GetWindowLong(IntPtr hWnd, int nIndex);
  [DllImport("user32.dll")] public static extern bool GetWindowPlacement(IntPtr hWnd, ref WINDOWPLACEMENT lpwndpl);
  [DllImport("user32.dll")] public static extern bool SetWindowPlacement(IntPtr hWnd, ref WINDOWPLACEMENT lpwndpl);
  [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr hwnd, int attr, out int value, int size);

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

  public static bool IsSkipClass(string cls) {
    if (string.IsNullOrEmpty(cls)) return true;
    switch (cls) {
      case "Progman":
      case "WorkerW":
      case "Shell_TrayWnd":
      case "Shell_SecondaryTrayWnd":
      case "NotifyIconOverflowWindow":
      case "TopLevelWindowForOverflowXamlIsland":
      case "DummyDWMListenerWindow":
      case "ForegroundStaging":
      case "MultitaskingViewFrame":
      case "Shell_InputSwitchTopLevelWindow":
      case "XamlExplorerHostIslandWindow":
      case "ApplicationManager_DesktopShellWindow":
      case "WindowsDashboard":
      case "ImmersiveLauncher":
      case "SearchPane":
      case "NativeHWNDHost":
      case "Shell_CharmWindow":
      case "EdgeUiInputTopWndClass":
      case "Windows.UI.Core.CoreWindow":
      case "IME":
      case "MSCTFIME UI":
      case "SysShadow":
        return true;
      default:
        return false;
    }
  }

  public static string ClassOf(IntPtr h) {
    var sb = new StringBuilder(256);
    GetClassName(h, sb, sb.Capacity);
    return sb.ToString();
  }

  public static string TitleOf(IntPtr h) {
    var sb = new StringBuilder(512);
    GetWindowText(h, sb, sb.Capacity);
    return sb.ToString();
  }

  public static bool IsCloaked(IntPtr h) {
    int cloaked;
    if (DwmGetWindowAttribute(h, DWMWA_CLOAKED, out cloaked, 4) != 0) return false;
    return cloaked != 0;
  }

  public static bool IsToolOnly(IntPtr h) {
    int ex = GetWindowLong(h, GWL_EXSTYLE);
    bool tool = (ex & WS_EX_TOOLWINDOW) != 0;
    bool app = (ex & WS_EX_APPWINDOW) != 0;
    return tool && !app;
  }

  public static bool HasSize(IntPtr h) {
    RECT r;
    if (!GetWindowRect(h, out r)) return false;
    return (r.Right - r.Left) >= 40 && (r.Bottom - r.Top) >= 40;
  }

  public static void ForceMin(IntPtr h) {
    if (h == IntPtr.Zero || !IsWindow(h) || IsIconic(h)) return;
    // Does not activate the next window (SW_MINIMIZE does, and that restores others).
    ShowWindow(h, SW_FORCEMINIMIZE);
    if (IsIconic(h)) return;
    ShowWindowAsync(h, SW_SHOWMINNOACTIVE);
    if (IsIconic(h)) return;
    PostMessage(h, WM_SYSCOMMAND, (IntPtr)SC_MINIMIZE, IntPtr.Zero);
    if (IsIconic(h)) return;
    WINDOWPLACEMENT wp = new WINDOWPLACEMENT();
    wp.length = Marshal.SizeOf(typeof(WINDOWPLACEMENT));
    if (!GetWindowPlacement(h, ref wp)) return;
    wp.showCmd = SW_SHOWMINIMIZED;
    wp.flags = wp.flags | WPF_ASYNCWINDOWPLACEMENT;
    SetWindowPlacement(h, ref wp);
  }
}
"@
}

$script:onlyProc = $OnlyProcess.Trim().ToLower()
$script:listOnly = [bool]$ListOnly
$script:procCache = @{}
$script:rows = New-Object System.Collections.Generic.List[string]
$script:hwndSet = New-Object 'System.Collections.Generic.HashSet[long]'
foreach ($part in ($OnlyHwnds -split '[,\s]+')) {
    if ([string]::IsNullOrWhiteSpace($part)) { continue }
    $n = 0L
    if ([long]::TryParse($part.Trim(), [ref]$n) -and $n -ne 0) {
        [void]$script:hwndSet.Add($n)
    }
}

$script:skipProcs = @('jarvis-gui', 'jarvis-app', 'jarvis-run', 'jarvis-gestures')

function Invoke-JarvisMinPass {
    $cb = {
        param($hwnd, $lp)
        if (-not [JarvisMinAllEx]::IsWindowVisible($hwnd)) { return $true }
        if ([JarvisMinAllEx]::IsIconic($hwnd)) { return $true }
        if (-not [JarvisMinAllEx]::HasSize($hwnd)) { return $true }
        if ([JarvisMinAllEx]::IsCloaked($hwnd)) { return $true }
        if ([JarvisMinAllEx]::IsToolOnly($hwnd)) { return $true }
        $cls = [JarvisMinAllEx]::ClassOf($hwnd)
        if ([JarvisMinAllEx]::IsSkipClass($cls)) { return $true }

        $procId = [uint32]0
        [void][JarvisMinAllEx]::GetWindowThreadProcessId($hwnd, [ref]$procId)
        $key = [int]$procId
        if (-not $script:procCache.ContainsKey($key)) {
            $nm = ""
            try {
                $nm = (Get-Process -Id $procId -ErrorAction Stop).ProcessName.ToLower()
            } catch {
                $nm = ""
            }
            $script:procCache[$key] = $nm
        }
        $nm = [string]$script:procCache[$key]
        if ($script:skipProcs -contains $nm) { return $true }
        if ($script:onlyProc -and $nm -ne $script:onlyProc) { return $true }
        $hid = $hwnd.ToInt64()
        if ($script:hwndSet.Count -gt 0 -and -not $script:hwndSet.Contains($hid)) { return $true }

        if ($script:listOnly) {
            $title = [JarvisMinAllEx]::TitleOf($hwnd) -replace "[\r\n\t]", " "
            [void]$script:rows.Add("$hid`t$procId`t$nm`t$cls`t$title")
            return $true
        }
        [JarvisMinAllEx]::ForceMin($hwnd)
        return $true
    }
    [void][JarvisMinAllEx]::EnumWindows($cb, [IntPtr]::Zero)
}

if ($ListOnly) {
    Invoke-JarvisMinPass
    $script:rows | ForEach-Object { $_ }
    exit 0
}

# Several passes: some apps (browsers) restore a sibling a moment after minimize.
Invoke-JarvisMinPass
Start-Sleep -Milliseconds 120
Invoke-JarvisMinPass
Start-Sleep -Milliseconds 200
Invoke-JarvisMinPass
Start-Sleep -Milliseconds 320
Invoke-JarvisMinPass
exit 0
