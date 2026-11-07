# Shared selection capture for TTS / translate (focus last non-JARVIS window + Ctrl+C).
# Dot-source from ASCII-only scripts only.
# IMPORTANT: never SW_RESTORE on a maximized window - that "shrinks" the browser/app.

function Initialize-JarvisSelectionCopy {
    if ("JarvisSelectCopy2" -as [type]) { return }
    Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Diagnostics;
using System.Runtime.InteropServices;
public static class JarvisSelectCopy2 {
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)]
  public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
  public const uint KEYEVENTF_KEYUP = 0x0002;
  public const byte VK_CONTROL = 0x11;
  public const byte VK_C = 0x43;
  public const int SW_SHOW = 5;
  public const int SW_RESTORE = 9;

  static bool IsJarvisProcess(string name) {
    name = (name ?? "").ToLowerInvariant();
    return name == "jarvis-gui" || name == "jarvis-app" || name == "jarvis-run";
  }

  public static IntPtr FindTargetWindow() {
    IntPtr fg = GetForegroundWindow();
    uint pid = 0;
    GetWindowThreadProcessId(fg, out pid);
    try {
      var p = Process.GetProcessById((int)pid);
      if (!IsJarvisProcess(p.ProcessName)) return fg;
    } catch {}

    IntPtr best = IntPtr.Zero;
    EnumWindows((hWnd, lParam) => {
      if (!IsWindowVisible(hWnd)) return true;
      uint wpid = 0;
      GetWindowThreadProcessId(hWnd, out wpid);
      try {
        var p = Process.GetProcessById((int)wpid);
        if (IsJarvisProcess(p.ProcessName)) return true;
      } catch { return true; }
      var title = new StringBuilder(256);
      GetWindowText(hWnd, title, title.Capacity);
      if (title.Length < 1) return true;
      best = hWnd;
      return false;
    }, IntPtr.Zero);
    return best != IntPtr.Zero ? best : fg;
  }

  public static void FocusAndCopy(IntPtr hWnd) {
    if (hWnd == IntPtr.Zero) return;
    uint unused = 0;
    uint curTid = GetCurrentThreadId();
    IntPtr fg = GetForegroundWindow();
    uint fgTid = fg != IntPtr.Zero ? GetWindowThreadProcessId(fg, out unused) : 0;
    uint targetTid = GetWindowThreadProcessId(hWnd, out unused);
    if (fgTid != 0 && fgTid != curTid) AttachThreadInput(curTid, fgTid, true);
    if (targetTid != 0 && targetTid != curTid && targetTid != fgTid) AttachThreadInput(curTid, targetTid, true);
    // Only restore when minimized. SW_RESTORE on a maximized window shrinks it.
    if (IsIconic(hWnd)) ShowWindow(hWnd, SW_RESTORE);
    else ShowWindow(hWnd, SW_SHOW);
    SetForegroundWindow(hWnd);
    System.Threading.Thread.Sleep(140);
    for (int i = 0; i < 2; i++) {
      keybd_event(VK_CONTROL, 0, 0, UIntPtr.Zero);
      keybd_event(VK_C, 0, 0, UIntPtr.Zero);
      keybd_event(VK_C, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
      keybd_event(VK_CONTROL, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
      System.Threading.Thread.Sleep(90);
    }
    System.Threading.Thread.Sleep(100);
    if (fgTid != 0 && fgTid != curTid) AttachThreadInput(curTid, fgTid, false);
    if (targetTid != 0 && targetTid != curTid && targetTid != fgTid) AttachThreadInput(curTid, targetTid, false);
  }
}
"@
}

function Get-JarvisClipboardTextSafe {
    for ($i = 0; $i -lt 6; $i++) {
        try {
            $clip = [System.Windows.Forms.Clipboard]::GetText()
            if ($null -ne $clip -and -not [string]::IsNullOrWhiteSpace($clip)) {
                return $clip.Trim()
            }
        } catch {}
        Start-Sleep -Milliseconds 60
    }
    return ""
}

function Get-JarvisSelectionOrClipboard {
    param(
        [string]$Preferred = "",
        [switch]$RestoreClipboard
    )

    if (-not [string]::IsNullOrWhiteSpace($Preferred)) {
        return $Preferred.Trim()
    }

    Initialize-JarvisSelectionCopy
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue

    $before = ""
    try { $before = [System.Windows.Forms.Clipboard]::GetText() } catch {}
    if ($null -eq $before) { $before = "" }
    $beforeTrim = $before.Trim()

    # Copied text already in the clipboard: do not send Ctrl+C (wipes it on many apps).
    if (-not [string]::IsNullOrWhiteSpace($beforeTrim)) {
        return $beforeTrim
    }

    $target = [JarvisSelectCopy2]::FindTargetWindow()
    try {
        [JarvisSelectCopy2]::FocusAndCopy($target)
    } catch {}

    $clip = Get-JarvisClipboardTextSafe
    $result = ""
    if (-not [string]::IsNullOrWhiteSpace($clip)) {
        $result = $clip
    }

    if ($RestoreClipboard) {
        try {
            if (-not [string]::IsNullOrEmpty($before)) {
                [System.Windows.Forms.Clipboard]::SetText($before)
            }
        } catch {}
    }

    return $result
}
