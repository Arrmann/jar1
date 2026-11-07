# Shared window geometry: work-area layouts + SetWindowPos after open.
# ASCII-only. Per-monitor DPI aware (physical pixels); work area comes from the
# monitor of the foreground window (MonitorFromWindow / GetForegroundWindow).
# The compiled helper is cached as a DLL so scenario runs skip csc.exe.

$script:JarvisWinGeomSource = @'
using System;
using System.IO;
using System.Text;
using System.Threading;
using System.Diagnostics;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class JarvisWinGeom {
  public const uint GA_ROOT = 2;
  public const int SW_RESTORE = 9;
  public const int SW_SHOW = 5;
  public const int SW_MAXIMIZE = 3;
  public const uint SWP_NOSIZE = 0x0001;
  public const uint SWP_NOMOVE = 0x0002;
  public const uint SWP_NOZORDER = 0x0004;
  public const uint SWP_NOACTIVATE = 0x0010;
  public const uint SWP_FRAMECHANGED = 0x0020;
  public const uint SWP_SHOWWINDOW = 0x0040;
  public const uint SPI_GETWORKAREA = 0x0030;
  public const int GWL_STYLE = -16;
  public const int GWL_EXSTYLE = -20;
  public const int WS_MAXIMIZE = 0x01000000;
  public const int WS_CAPTION = 0x00C00000;
  public const int WS_THICKFRAME = 0x00040000;
  public const int WS_EX_TOPMOST = 0x00000008;
  public const int WS_EX_TOOLWINDOW = 0x00000080;
  public const int WS_EX_NOACTIVATE = 0x08000000;
  public const uint GW_OWNER = 4;
  public const uint MONITOR_DEFAULTTONEAREST = 2;
  public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);

  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc lpEnumFunc, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
  [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr hwnd, uint gaFlags);
  [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr hWnd, uint uCmd);
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr hWnd, int nIndex);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int X, int Y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool SystemParametersInfo(uint uiAction, uint uiParam, ref RECT pvParam, uint fWinIni);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
  [DllImport("user32.dll")] public static extern IntPtr GetShellWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);
  [DllImport("user32.dll")] public static extern IntPtr MonitorFromWindow(IntPtr hwnd, uint dwFlags);
  [DllImport("user32.dll")] public static extern IntPtr MonitorFromPoint(POINT pt, uint dwFlags);
  [DllImport("user32.dll")] public static extern bool GetMonitorInfo(IntPtr hMonitor, ref MONITORINFO lpmi);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] static extern bool BringWindowToTop(IntPtr hWnd);
  [DllImport("user32.dll")] static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
  [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr ctx);
  [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr hwnd, int attr, out RECT value, int size);
  [DllImport("dwmapi.dll", EntryPoint = "DwmGetWindowAttribute")] static extern int DwmGetWindowAttributeInt(IntPtr hwnd, int attr, out int value, int size);
  [DllImport("shcore.dll")] static extern int GetDpiForMonitor(IntPtr hmon, int type, out uint dpiX, out uint dpiY);
  [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, uint pid);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern bool QueryFullProcessImageName(IntPtr h, uint flags, StringBuilder name, ref int size);

  [StructLayout(LayoutKind.Sequential)]
  public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)]
  public struct POINT { public int X, Y; }
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
  public struct MONITORINFO {
    public int cbSize;
    public RECT rcMonitor;
    public RECT rcWork;
    public uint dwFlags;
  }

  [ThreadStatic] static bool dpiReady;

  /// Physical pixels everywhere; otherwise a DPI-unaware host gets scaled rects.
  public static void EnsureDpi() {
    if (dpiReady) return;
    dpiReady = true;
    try { SetThreadDpiAwarenessContext(new IntPtr(-4)); } catch { }
  }

  public static List<long> ListTopHwnds() {
    EnsureDpi();
    var list = new List<long>();
    IntPtr shell = GetShellWindow();
    EnumWindows((h, _) => {
      if (!IsWindowVisible(h)) return true;
      if (h == shell) return true;
      IntPtr root = GetAncestor(h, GA_ROOT);
      if (root != IntPtr.Zero && root != h) return true;
      if (GetWindowTextLength(h) <= 0) return true;
      var cls = new StringBuilder(64);
      GetClassName(h, cls, cls.Capacity);
      string c = cls.ToString();
      if (c == "Progman" || c == "WorkerW" || c == "Shell_TrayWnd" || c == "NotifyIconOverflowWindow") return true;
      list.Add(h.ToInt64());
      return true;
    }, IntPtr.Zero);
    return list;
  }

  /// Visible frame (without the invisible resize border of Win10/11).
  public static bool Frame(IntPtr h, out RECT r) {
    EnsureDpi();
    try {
      if (DwmGetWindowAttribute(h, 9, out r, Marshal.SizeOf(typeof(RECT))) == 0 && r.Right > r.Left) return true;
    } catch { }
    return GetWindowRect(h, out r);
  }

  public static bool IsCloaked(IntPtr h) {
    try {
      int v;
      if (DwmGetWindowAttributeInt(h, 14, out v, 4) == 0) return v != 0;
    } catch { }
    return false;
  }

  public static string ExeOfPid(uint pid) {
    IntPtr hp = OpenProcess(0x1000, false, pid);
    if (hp == IntPtr.Zero) return "";
    try {
      var sb = new StringBuilder(1024);
      int size = sb.Capacity;
      if (!QueryFullProcessImageName(hp, 0, sb, ref size)) return "";
      return Path.GetFileName(sb.ToString()).ToLowerInvariant();
    } catch {
      return "";
    } finally {
      CloseHandle(hp);
    }
  }

  /// Place so the *visible* frame lands on x/y/w/h (compensates DWM borders).
  public static void PlaceFrame(IntPtr hWnd, int x, int y, int w, int h, bool resize) {
    EnsureDpi();
    if (IsIconic(hWnd) || IsZoomed(hWnd)) ShowWindow(hWnd, SW_RESTORE);
    uint flags = SWP_NOZORDER | SWP_NOACTIVATE | SWP_SHOWWINDOW;
    for (int pass = 0; pass < 2; pass++) {
      RECT wr, fr;
      int l = 0, t = 0, r = 0, b = 0;
      if (GetWindowRect(hWnd, out wr) && Frame(hWnd, out fr)) {
        l = fr.Left - wr.Left; t = fr.Top - wr.Top; r = wr.Right - fr.Right; b = wr.Bottom - fr.Bottom;
        if (l < 0 || t < 0 || r < 0 || b < 0 || l > 40 || t > 40 || r > 40 || b > 40) { l = t = r = b = 0; }
      } else {
        fr = new RECT();
      }
      if (resize) {
        SetWindowPos(hWnd, IntPtr.Zero, x - l, y - t, w + l + r, h + t + b, flags);
      } else {
        int cw = fr.Right - fr.Left, ch = fr.Bottom - fr.Top;
        int nx = x + Math.Max(0, (w - cw) / 2), ny = y + Math.Max(0, (h - ch) / 2);
        SetWindowPos(hWnd, IntPtr.Zero, nx - l, ny - t, 0, 0, flags | SWP_NOSIZE);
      }
      // Crossing monitors with different DPI changes the border; one more pass fixes it.
      RECT now;
      if (!resize || !Frame(hWnd, out now)) break;
      if (Math.Abs(now.Left - x) <= 2 && Math.Abs(now.Top - y) <= 2 &&
          Math.Abs(now.Right - (x + w)) <= 2 && Math.Abs(now.Bottom - (y + h)) <= 2) break;
    }
  }

  /// A hidden background process is not allowed to steal focus; borrow the input queue.
  public static void Activate(IntPtr hWnd) {
    IntPtr fg = GetForegroundWindow();
    if (fg == hWnd) return;
    uint ignored;
    uint fgThread = fg == IntPtr.Zero ? 0 : GetWindowThreadProcessId(fg, out ignored);
    uint self = GetCurrentThreadId();
    bool attached = fgThread != 0 && fgThread != self && AttachThreadInput(self, fgThread, true);
    try {
      BringWindowToTop(hWnd);
      SetForegroundWindow(hWnd);
    } finally {
      if (attached) AttachThreadInput(self, fgThread, false);
    }
  }

  public static bool Place(IntPtr hWnd, int x, int y, int w, int h, bool maximize) {
    if (hWnd == IntPtr.Zero || !IsWindow(hWnd)) return false;
    IntPtr root = GetAncestor(hWnd, GA_ROOT);
    if (root != IntPtr.Zero && IsWindow(root)) hWnd = root;
    if (maximize) {
      ShowWindow(hWnd, SW_RESTORE);
      ShowWindow(hWnd, SW_MAXIMIZE);
      SetForegroundWindow(hWnd);
      return true;
    }
    if (w < 200) w = 200;
    if (h < 120) h = 120;
    ClampToWorkArea(ref x, ref y, ref w, ref h);
    PlaceFrame(hWnd, x, y, w, h, true);
    SetForegroundWindow(hWnd);
    return true;
  }

  public static RECT WorkArea() {
    EnsureDpi();
    // Prefer the monitor of the foreground window (multi-PC / multi-monitor safe).
    IntPtr fg = GetForegroundWindow();
    if (fg != IntPtr.Zero) {
      IntPtr mon = MonitorFromWindow(fg, MONITOR_DEFAULTTONEAREST);
      MONITORINFO mi = new MONITORINFO();
      mi.cbSize = Marshal.SizeOf(typeof(MONITORINFO));
      if (mon != IntPtr.Zero && GetMonitorInfo(mon, ref mi)) return mi.rcWork;
    }
    RECT wa = new RECT();
    SystemParametersInfo(SPI_GETWORKAREA, 0, ref wa, 0);
    return wa;
  }

  public static RECT WorkAreaForPoint(int x, int y) {
    EnsureDpi();
    POINT pt; pt.X = x; pt.Y = y;
    IntPtr mon = MonitorFromPoint(pt, MONITOR_DEFAULTTONEAREST);
    MONITORINFO mi = new MONITORINFO();
    mi.cbSize = Marshal.SizeOf(typeof(MONITORINFO));
    if (mon != IntPtr.Zero && GetMonitorInfo(mon, ref mi)) return mi.rcWork;
    return WorkArea();
  }

  public static RECT MonitorRectOf(IntPtr h) {
    IntPtr mon = MonitorFromWindow(h, MONITOR_DEFAULTTONEAREST);
    MONITORINFO mi = new MONITORINFO();
    mi.cbSize = Marshal.SizeOf(typeof(MONITORINFO));
    if (mon != IntPtr.Zero && GetMonitorInfo(mon, ref mi)) return mi.rcMonitor;
    return WorkArea();
  }

  /// Monitor scale at a physical point (1.0 = 96 dpi). Chromium flags take DIPs.
  public static double ScaleAt(int x, int y) {
    EnsureDpi();
    try {
      POINT pt; pt.X = x; pt.Y = y;
      IntPtr mon = MonitorFromPoint(pt, MONITOR_DEFAULTTONEAREST);
      uint dx, dy;
      if (mon != IntPtr.Zero && GetDpiForMonitor(mon, 0, out dx, out dy) == 0 && dx >= 96) return dx / 96.0;
    } catch { }
    return 1.0;
  }

  /// Keep window fully visible on some monitor work area (stops off-screen placements).
  public static void ClampToWorkArea(ref int x, ref int y, ref int w, ref int h) {
    if (w < 200) w = 200;
    if (h < 120) h = 120;
    RECT wa = WorkAreaForPoint(x + w / 2, y + h / 2);
    int waW = Math.Max(320, wa.Right - wa.Left);
    int waH = Math.Max(240, wa.Bottom - wa.Top);
    if (w > waW) w = waW;
    if (h > waH) h = waH;
    if (x < wa.Left) x = wa.Left;
    if (y < wa.Top) y = wa.Top;
    if (x + w > wa.Right) x = wa.Right - w;
    if (y + h > wa.Bottom) y = wa.Bottom - h;
    if (x < wa.Left) x = wa.Left;
    if (y < wa.Top) y = wa.Top;
  }

  // Studio layout (fractions of the work area): x, y, w, h, z (higher = on top).
  // 1: top-left small, 2: center-bottom overlapping, 3: big right, 4: over the right.
  static readonly double[][] Studio = new double[][] {
    new double[] { 0.000, 0.000, 0.335, 0.425, 2 },
    new double[] { 0.150, 0.385, 0.365, 0.615, 3 },
    new double[] { 0.425, 0.000, 0.575, 1.000, 0 },
    new double[] { 0.470, 0.040, 0.530, 0.960, 1 },
  };

  /// Rect for auto slot `index` of `count`: [x, y, w, h, z] in physical pixels.
  public static int[] Layout(int index, int count, RECT wa) {
    if (count < 1) count = 1;
    if (index < 0) index = 0;
    if (index >= count) index = count - 1;
    int W = Math.Max(320, wa.Right - wa.Left), H = Math.Max(240, wa.Bottom - wa.Top);
    int m = Math.Max(6, (int)Math.Round(Math.Min(W, H) * 0.008));
    double ix = wa.Left + m, iy = wa.Top + m, iw = W - 2 * m, ih = H - 2 * m;
    double[] f;
    if (count == 1) {
      f = new double[] { 0.04, 0.03, 0.92, 0.94, 0 };
    } else if (count == 2) {
      f = index == 0 ? new double[] { 0.0, 0.0, 0.415, 1.0, 0 } : new double[] { 0.425, 0.0, 0.575, 1.0, 1 };
    } else if (count <= 4) {
      f = Studio[index];
    } else {
      int cols = count <= 9 ? 3 : 4;
      int rows = (count + cols - 1) / cols;
      double g = m / iw, gy = m / ih;
      double cw = (1.0 - (cols - 1) * g) / cols, ch = (1.0 - (rows - 1) * gy) / rows;
      int col = index % cols, row = index / cols;
      f = new double[] { col * (cw + g), row * (ch + gy), cw, ch, index };
    }
    return new int[] {
      (int)Math.Round(ix + f[0] * iw), (int)Math.Round(iy + f[1] * ih),
      (int)Math.Round(f[2] * iw), (int)Math.Round(f[3] * ih), (int)f[4]
    };
  }
}

public sealed class JarvisSlot {
  public string Match = "any";
  public HashSet<string> Exes = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
  public bool Maximize;
  public int X, Y, W, H, Z;
  public IntPtr Hwnd = IntPtr.Zero;
  public string HwndExe = "";
  public long CreatedMs, DeadlineMs, PlacedMs;
  public int Fixes;
}

/// Claims windows for scenario steps as they appear and keeps them in their slots.
/// match: "exe" (process file name), "browser" (new browser window), "any" (any new window).
public sealed class JarvisLayoutRun {
  static readonly HashSet<string> Browsers = new HashSet<string>(StringComparer.OrdinalIgnoreCase) {
    "chrome.exe", "msedge.exe", "browser.exe", "firefox.exe", "opera.exe", "brave.exe", "vivaldi.exe", "yandex.exe", "arc.exe"
  };
  static readonly HashSet<string> Ignored = new HashSet<string>(StringComparer.OrdinalIgnoreCase) {
    "powershell.exe", "pwsh.exe", "conhost.exe", "openconsole.exe", "windowsterminal.exe", "cmd.exe",
    "textinputhost.exe", "shellexperiencehost.exe", "startmenuexperiencehost.exe", "searchhost.exe",
    "searchapp.exe", "lockapp.exe"
  };
  const int WatchAfterPlaceMs = 3000;

  readonly HashSet<long> before;
  readonly HashSet<long> taken = new HashSet<long>();
  readonly Dictionary<uint, string> exeByPid = new Dictionary<uint, string>();
  readonly List<JarvisSlot> slots = new List<JarvisSlot>();
  readonly Stopwatch clock = Stopwatch.StartNew();
  readonly uint selfPid = (uint)Process.GetCurrentProcess().Id;
  long lastEventMs;
  bool restack;
  readonly object gate = new object();
  volatile bool stopping;
  Thread worker;
  int quietMsForSettle;

  /// "ms exe" per claimed window, for diagnostics.
  public readonly List<string> Events = new List<string>();

  sealed class Cand { public IntPtr H; public string Exe; public bool Used; }

  public JarvisLayoutRun(long[] beforeHwnds) {
    JarvisWinGeom.EnsureDpi();
    before = new HashSet<long>(beforeHwnds ?? new long[0]);
  }

  /// Snapshot current windows and start placing on a background thread, so a slow
  /// step (browser, wait) never delays windows that are already on screen.
  public static JarvisLayoutRun Start() {
    var run = new JarvisLayoutRun(JarvisWinGeom.ListTopHwnds().ToArray());
    run.worker = new Thread(run.Loop);
    run.worker.IsBackground = true;
    run.worker.Start();
    return run;
  }

  void Loop() {
    while (!stopping) {
      try { Pass(); } catch { }
      Thread.Sleep(40);
    }
  }

  long Now { get { return clock.ElapsedMilliseconds; } }

  public JarvisSlot AddSlot(string match, string exes, bool maximize, int x, int y, int w, int h, int z) {
    lock (gate) { return AddSlotLocked(match, exes, maximize, x, y, w, h, z); }
  }

  JarvisSlot AddSlotLocked(string match, string exes, bool maximize, int x, int y, int w, int h, int z) {
    var s = new JarvisSlot();
    s.Match = string.IsNullOrEmpty(match) ? "any" : match.ToLowerInvariant();
    foreach (string e in (exes ?? "").Split(new char[] { ',', ';' }, StringSplitOptions.RemoveEmptyEntries)) {
      string t = e.Trim();
      if (t.Length > 0) s.Exes.Add(t);
    }
    if (s.Match == "exe" && s.Exes.Count == 0) s.Match = "any";
    s.Maximize = maximize;
    s.X = x; s.Y = y; s.W = w; s.H = h; s.Z = z;
    s.CreatedMs = Now;
    s.DeadlineMs = s.CreatedMs + (s.Match == "browser" ? 6000 : 15000);
    slots.Add(s);
    return s;
  }

  string ExeOf(IntPtr h, out uint pid) {
    GetPid(h, out pid);
    string exe;
    if (!exeByPid.TryGetValue(pid, out exe)) {
      exe = JarvisWinGeom.ExeOfPid(pid);
      exeByPid[pid] = exe;
    }
    return exe;
  }

  static void GetPid(IntPtr h, out uint pid) { JarvisWinGeom.GetWindowThreadProcessId(h, out pid); }

  bool Eligible(IntPtr h, out string exe) {
    exe = "";
    if (!JarvisWinGeom.IsWindowVisible(h)) return false;
    if (JarvisWinGeom.GetWindow(h, JarvisWinGeom.GW_OWNER) != IntPtr.Zero) return false;
    int ex = JarvisWinGeom.GetWindowLong(h, JarvisWinGeom.GWL_EXSTYLE);
    if ((ex & (JarvisWinGeom.WS_EX_TOOLWINDOW | JarvisWinGeom.WS_EX_NOACTIVATE | JarvisWinGeom.WS_EX_TOPMOST)) != 0) return false;
    if (JarvisWinGeom.IsCloaked(h)) return false;
    uint pid;
    exe = ExeOf(h, out pid);
    if (pid == selfPid) return false;
    if (exe.StartsWith("jarvis") || Ignored.Contains(exe)) return false;
    JarvisWinGeom.RECT fr;
    if (!JarvisWinGeom.Frame(h, out fr)) return false;
    int w = fr.Right - fr.Left, hh = fr.Bottom - fr.Top;
    if (!JarvisWinGeom.IsIconic(h) && (w < 320 || hh < 200)) return false;
    // Borderless fullscreen (games): leave alone.
    int style = JarvisWinGeom.GetWindowLong(h, JarvisWinGeom.GWL_STYLE);
    if ((style & JarvisWinGeom.WS_CAPTION) != JarvisWinGeom.WS_CAPTION) {
      JarvisWinGeom.RECT mr = JarvisWinGeom.MonitorRectOf(h);
      if (Math.Abs(fr.Left - mr.Left) <= 2 && Math.Abs(fr.Top - mr.Top) <= 2 &&
          Math.Abs(fr.Right - mr.Right) <= 2 && Math.Abs(fr.Bottom - mr.Bottom) <= 2) return false;
    }
    return true;
  }

  bool Pending(JarvisSlot s, long now) { return s.Hwnd == IntPtr.Zero && now < s.DeadlineMs; }

  bool WantedByOther(JarvisSlot self, string exe, long now) {
    foreach (var s in slots) {
      if (s == self || !Pending(s, now)) continue;
      if (s.Match == "exe" && s.Exes.Contains(exe)) return true;
      if (s.Match == "browser" && Browsers.Contains(exe)) return true;
    }
    return false;
  }

  void Claim(JarvisSlot s, Cand c, long now) {
    c.Used = true;
    s.Hwnd = c.H;
    s.HwndExe = c.Exe;
    s.PlacedMs = now;
    s.Fixes = 0;
    taken.Add(c.H.ToInt64());
    Apply(s);
    lastEventMs = now;
    restack = true;
    Events.Add(now + " " + (c.Exe.Length > 0 ? c.Exe : "?"));
  }

  static bool Resizable(IntPtr h) {
    return (JarvisWinGeom.GetWindowLong(h, JarvisWinGeom.GWL_STYLE) & JarvisWinGeom.WS_THICKFRAME) != 0;
  }

  static void Apply(JarvisSlot s) {
    if (s.Maximize) {
      if (!JarvisWinGeom.IsZoomed(s.Hwnd)) JarvisWinGeom.ShowWindow(s.Hwnd, JarvisWinGeom.SW_MAXIMIZE);
      return;
    }
    JarvisWinGeom.PlaceFrame(s.Hwnd, s.X, s.Y, s.W, s.H, Resizable(s.Hwnd));
  }

  static bool Drifted(JarvisSlot s) {
    if (s.Maximize) return !JarvisWinGeom.IsZoomed(s.Hwnd);
    if (JarvisWinGeom.IsIconic(s.Hwnd) || JarvisWinGeom.IsZoomed(s.Hwnd)) return true;
    if (!Resizable(s.Hwnd)) return false;
    JarvisWinGeom.RECT fr;
    if (!JarvisWinGeom.Frame(s.Hwnd, out fr)) return false;
    return Math.Abs(fr.Left - s.X) > 10 || Math.Abs(fr.Top - s.Y) > 10 ||
           Math.Abs(fr.Right - (s.X + s.W)) > 10 || Math.Abs(fr.Bottom - (s.Y + s.H)) > 10;
  }

  void ClaimNew(long now) {
    var fresh = new List<Cand>();
    var old = new List<Cand>();
    foreach (long v in JarvisWinGeom.ListTopHwnds()) {
      if (taken.Contains(v)) continue;
      IntPtr h = new IntPtr(v);
      string exe;
      if (!Eligible(h, out exe)) continue;
      var c = new Cand();
      c.H = h; c.Exe = exe;
      if (before.Contains(v)) old.Add(c); else fresh.Add(c);
    }
    if (fresh.Count == 0 && old.Count == 0) return;
    IntPtr fg = JarvisWinGeom.GetForegroundWindow();

    // Exact app match first, then browsers, then "whatever just opened".
    foreach (var s in slots) {
      if (!Pending(s, now) || s.Match != "exe") continue;
      foreach (var c in fresh) { if (!c.Used && s.Exes.Contains(c.Exe)) { Claim(s, c, now); break; } }
    }
    // Several browser windows can land in one scan; Chromium already opened each
    // near its own slot (--window-position), so the closest one belongs to it.
    foreach (var s in slots) {
      if (!Pending(s, now) || s.Match != "browser") continue;
      Cand best = null;
      long bestDist = long.MaxValue;
      foreach (var c in fresh) {
        if (c.Used || !Browsers.Contains(c.Exe)) continue;
        JarvisWinGeom.RECT fr;
        long d = JarvisWinGeom.Frame(c.H, out fr)
          ? Math.Abs((long)fr.Left - s.X) + Math.Abs((long)fr.Top - s.Y) + Math.Abs((long)(fr.Right - fr.Left) - s.W)
          : long.MaxValue - 1;
        if (best == null || d < bestDist) { best = c; bestDist = d; }
      }
      if (best != null) Claim(s, best, now);
    }
    foreach (var s in slots) {
      if (!Pending(s, now) || s.Match != "any") continue;
      foreach (var c in fresh) { if (!c.Used && !WantedByOther(s, c.Exe, now)) { Claim(s, c, now); break; } }
    }
    // Already running app: relaunch only re-activates its old window.
    foreach (var s in slots) {
      if (!Pending(s, now) || s.Match != "exe" || s.Exes.Contains("explorer.exe")) continue;
      Cand pick = null;
      foreach (var c in old) {
        if (c.Used || !s.Exes.Contains(c.Exe)) continue;
        if (c.H == fg) { pick = c; break; }
        if (pick == null) pick = c;
      }
      if (pick != null && (pick.H == fg || now - s.CreatedMs >= 900)) Claim(s, pick, now);
    }
    // Launchers whose window belongs to another exe.
    foreach (var s in slots) {
      if (!Pending(s, now) || s.Match != "exe" || now - s.CreatedMs < 3000) continue;
      foreach (var c in fresh) {
        if (!c.Used && !Browsers.Contains(c.Exe) && !WantedByOther(s, c.Exe, now)) { Claim(s, c, now); break; }
      }
    }
  }

  void Restack() {
    restack = false;
    var placed = new List<JarvisSlot>();
    foreach (var s in slots) if (s.Hwnd != IntPtr.Zero && JarvisWinGeom.IsWindow(s.Hwnd)) placed.Add(s);
    if (placed.Count == 0) return;
    placed.Sort((a, b) => a.Z.CompareTo(b.Z));
    foreach (var s in placed) {
      JarvisWinGeom.SetWindowPos(s.Hwnd, IntPtr.Zero, 0, 0, 0, 0,
        JarvisWinGeom.SWP_NOMOVE | JarvisWinGeom.SWP_NOSIZE | JarvisWinGeom.SWP_NOACTIVATE);
    }
    JarvisWinGeom.Activate(placed[placed.Count - 1].Hwnd);
  }

  bool ForegroundIsOurs() {
    IntPtr fg = JarvisWinGeom.GetForegroundWindow();
    foreach (var s in slots) if (s.Hwnd != IntPtr.Zero && s.Hwnd == fg) return true;
    return false;
  }

  /// One scan: claim new windows, re-fix ones the app moved back.
  public void Pass() {
    lock (gate) { PassLocked(); }
  }

  void PassLocked() {
    long now = Now;
    foreach (var s in slots) {
      if (s.Hwnd == IntPtr.Zero) continue;
      if (!JarvisWinGeom.IsWindow(s.Hwnd) || !JarvisWinGeom.IsWindowVisible(s.Hwnd)) {
        // Splash / updater closed - wait for the real window of the same app.
        if (s.Match == "any" && s.HwndExe.Length > 0) { s.Match = "exe"; s.Exes.Add(s.HwndExe); }
        s.Hwnd = IntPtr.Zero;
        s.DeadlineMs = Math.Max(s.DeadlineMs, now + 8000);
        continue;
      }
      if (now - s.PlacedMs < WatchAfterPlaceMs && s.Fixes < 4 && Drifted(s)) {
        Apply(s);
        s.Fixes++;
        lastEventMs = now;
      }
    }
    foreach (var s in slots) {
      if (Pending(s, now)) { ClaimNew(now); break; }
    }
    if (!restack && now - lastEventMs < WatchAfterPlaceMs && ForegroundIsOurs() && !TopIsForeground()) restack = true;
    if (restack) Restack();
  }

  bool TopIsForeground() {
    JarvisSlot top = null;
    foreach (var s in slots) {
      if (s.Hwnd == IntPtr.Zero || !JarvisWinGeom.IsWindow(s.Hwnd)) continue;
      if (top == null || s.Z >= top.Z) top = s;
    }
    return top == null || top.Hwnd == JarvisWinGeom.GetForegroundWindow();
  }

  bool Busy(long now) {
    foreach (var s in slots) {
      if (Pending(s, now)) return true;
      if (s.Hwnd != IntPtr.Zero && now - s.PlacedMs < WatchAfterPlaceMs && s.Fixes < 4) return true;
    }
    return now - lastEventMs < quietMsForSettle;
  }

  /// Block until every slot is placed (or gave up) and windows stopped moving.
  public void Settle(int maxMs, int quietMs) {
    long end = Now + Math.Max(0, maxMs);
    while (true) {
      bool busy;
      lock (gate) {
        quietMsForSettle = quietMs;
        busy = Busy(Now);
      }
      if (!busy || Now >= end) break;
      Thread.Sleep(40);
    }
    stopping = true;
    if (worker != null) worker.Join(500);
    lock (gate) {
      // Apps activate themselves after showing; restore the intended stacking
      // unless the user has already switched to something else.
      if (ForegroundIsOurs()) Restack();
    }
  }
}
'@

function Import-JarvisWinGeomType {
    if ("JarvisLayoutRun" -as [type]) { return $true }
    $src = $script:JarvisWinGeomSource
    try {
        $md5 = [Security.Cryptography.MD5]::Create()
        $hash = ([BitConverter]::ToString($md5.ComputeHash([Text.Encoding]::UTF8.GetBytes($src))) -replace '-', '').Substring(0, 16)
        $dir = "C:\ProgramData\JARVIS\pscache"
        if (Get-Command Set-JarvisAsciiTemp -ErrorAction SilentlyContinue) {
            $got = Set-JarvisAsciiTemp
            if ($got) { $dir = $got }
        } else {
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
            $env:TEMP = $dir
            $env:TMP = $dir
        }
        $dll = Join-Path $dir "JarvisWinGeom-$hash.dll"
        if (-not (Test-Path -LiteralPath $dll)) {
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
            $tmp = Join-Path $dir ("JarvisWinGeom-{0}-{1}.tmp.dll" -f $hash, $PID)
            Add-Type -TypeDefinition $src -OutputAssembly $tmp -OutputType Library -ErrorAction Stop
            try { Move-Item -LiteralPath $tmp -Destination $dll -Force -ErrorAction Stop } catch {
                # Parallel run already published the same build.
                Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
            }
        }
        Add-Type -Path $dll -ErrorAction Stop
        return $true
    } catch {
        try {
            Add-Type -TypeDefinition $src -ErrorAction Stop
            return $true
        } catch {
            Write-Warning "JARVIS window geom skipped (Device Guard / Add-Type): $($_.Exception.Message)"
            return $false
        }
    }
}

[void](Import-JarvisWinGeomType)

function Get-JarvisVisibleHwndSet {
    $set = @{}
    if (-not ("JarvisWinGeom" -as [type])) { return $set }
    foreach ($h in [JarvisWinGeom]::ListTopHwnds()) {
        $set["$h"] = $true
    }
    return $set
}

function Get-JarvisWorkAreaTile {
    param([int]$Index = 0, [int]$Count = 1)
    $r = [JarvisWinGeom]::Layout($Index, [Math]::Max(1, $Count), [JarvisWinGeom]::WorkArea())
    return @{ X = $r[0]; Y = $r[1]; W = $r[2]; H = $r[3] }
}

$script:JarvisShellApp = $null

# .lnk -> @{ Path; Arguments }. Shell.Application copes with relative/Unicode links
# that WScript.Shell returns empty for.
function Resolve-JarvisShortcut([string]$Path) {
    try {
        if ($null -eq $script:JarvisShellApp) { $script:JarvisShellApp = New-Object -ComObject Shell.Application }
        $item = $script:JarvisShellApp.NameSpace([IO.Path]::GetDirectoryName($Path)).ParseName([IO.Path]::GetFileName($Path))
        if ($item -and $item.IsLink) {
            $link = $item.GetLink
            if ($link -and $link.Path) { return @{ Path = [string]$link.Path; Arguments = [string]$link.Arguments } }
        }
    } catch {}
    try {
        $s = (New-Object -ComObject WScript.Shell).CreateShortcut($Path)
        if ($s.TargetPath) { return @{ Path = [string]$s.TargetPath; Arguments = [string]$s.Arguments } }
    } catch {}
    return $null
}

# How to recognise the window a step opens: @{ Match = exe|browser|any; Exes = "a.exe,b.exe" }.
function Get-JarvisSlotMatch([string]$Kind, [string]$Target) {
    $k = ("$Kind").Trim().ToLowerInvariant()
    $t = ("$Target").Trim().Trim('"')
    if ($k -eq "url" -or $k -eq "search") { return @{ Match = "browser"; Exes = "" } }
    if ($k -eq "folder") { return @{ Match = "any"; Exes = "" } }
    if ($t -match '^[a-zA-Z][a-zA-Z0-9+.-]+:' -and $t -notmatch '^[a-zA-Z]:[\\/]') { return @{ Match = "any"; Exes = "" } }

    $ext = ""
    try { $ext = [IO.Path]::GetExtension($t).ToLowerInvariant() } catch {}
    $exePath = $null
    $linkArgs = ""
    if ($ext -eq ".lnk") {
        $link = Resolve-JarvisShortcut $t
        if ($link) { $exePath = $link.Path; $linkArgs = $link.Arguments }
    } elseif ($ext -eq ".exe") {
        $exePath = $t
    } elseif ($k -eq "app" -and $ext -eq "" -and $t -notmatch '[\\/]') {
        $exePath = "$t.exe"
    }
    if (-not $exePath -or -not $exePath.ToLowerInvariant().EndsWith(".exe")) { return @{ Match = "any"; Exes = "" } }

    $name = [IO.Path]::GetFileName($exePath).ToLowerInvariant()
    if ($name -eq "explorer.exe") { return @{ Match = "any"; Exes = "" } }
    $names = @($name)
    # Squirrel apps (Discord, etc.): Update.exe --processStart Real.exe
    if ($name -eq "update.exe" -and $linkArgs -match '--processStart\s+"?([^"\s]+)') {
        $names = @($Matches[1].ToLowerInvariant())
    }
    if ($name -eq "steam.exe") { $names += "steamwebhelper.exe" }
    return @{ Match = "exe"; Exes = ($names -join ",") }
}

function Wait-JarvisNewWindow {
    param(
        [hashtable]$BeforeSet,
        [int]$TimeoutMs = 220
    )
    if (-not ("JarvisWinGeom" -as [type])) { return [IntPtr]::Zero }
    $deadline = (Get-Date).AddMilliseconds([Math]::Max(80, $TimeoutMs))
    while ((Get-Date) -lt $deadline) {
        foreach ($h in [JarvisWinGeom]::ListTopHwnds()) {
            if ($BeforeSet.ContainsKey("$h")) { continue }
            $hwnd = [IntPtr]$h
            if (-not [JarvisWinGeom]::IsWindow($hwnd)) { continue }
            $rc = New-Object JarvisWinGeom+RECT
            if (-not [JarvisWinGeom]::GetWindowRect($hwnd, [ref]$rc)) { continue }
            if (($rc.Right - $rc.Left) -lt 80 -or ($rc.Bottom - $rc.Top) -lt 40) { continue }
            return $hwnd
        }
        Start-Sleep -Milliseconds 12
    }
    return [IntPtr]::Zero
}

function Place-JarvisWindow {
    param(
        [IntPtr]$Hwnd,
        [int]$X,
        [int]$Y,
        [int]$W,
        [int]$H,
        [switch]$Maximize
    )
    if ($Hwnd -eq [IntPtr]::Zero) { return $false }
    if (-not ("JarvisWinGeom" -as [type])) { return $false }
    return [JarvisWinGeom]::Place($Hwnd, $X, $Y, $W, $H, [bool]$Maximize)
}

function Invoke-JarvisPlaceAfterOpen {
    param(
        [hashtable]$BeforeSet,
        [string]$Mode = "auto",
        [int]$X = 0,
        [int]$Y = 0,
        [int]$W = 0,
        [int]$H = 0,
        [int]$TileIndex = 0,
        [int]$TileCount = 1,
        [int]$TimeoutMs = 220
    )
    $mode = ("$Mode").Trim().ToLowerInvariant()
    if ($mode -eq "" -or $mode -eq "none" -or $mode -eq "off") { return $false }
    if (-not ("JarvisWinGeom" -as [type])) { return $false }

    $hwnd = Wait-JarvisNewWindow -BeforeSet $BeforeSet -TimeoutMs $TimeoutMs
    if ($hwnd -eq [IntPtr]::Zero) { return $false }

    if ($mode -eq "max" -or $mode -eq "maximize") {
        return Place-JarvisWindow -Hwnd $hwnd -X 0 -Y 0 -W 0 -H 0 -Maximize
    }
    if ($mode -eq "custom" -and $W -ge 200 -and $H -ge 120) {
        return Place-JarvisWindow -Hwnd $hwnd -X $X -Y $Y -W $W -H $H
    }
    $tile = Get-JarvisWorkAreaTile -Index $TileIndex -Count ([Math]::Max(1, $TileCount))
    return Place-JarvisWindow -Hwnd $hwnd -X $tile.X -Y $tile.Y -W $tile.W -H $tile.H
}
