# JARVIS brightness - laptop WMI (verified), desktop DDC/CI (verified), gamma assist.
# Laptop panels often look flat at WMI 10..50 - we remap + add gamma so steps differ.
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Value
)

$ErrorActionPreference = "Continue"
. (Join-Path $PSScriptRoot "_jarvis-data-dir.ps1")
$StateFile = Join-Path (Get-JarvisDataDir) "brightness.last"

function Read-VirtualBrightness {
    if (-not (Test-Path -LiteralPath $StateFile)) { return 50 }
    $raw = (Get-Content -LiteralPath $StateFile -Raw -ErrorAction SilentlyContinue).Trim()
    $n = 0
    if ([int]::TryParse($raw, [ref]$n)) { return [Math]::Max(0, [Math]::Min(100, $n)) }
    return 50
}

function Save-VirtualBrightness([int]$Pct) {
    try {
        $dir = Split-Path -Parent $StateFile
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Set-Content -LiteralPath $StateFile -Value ([string]$Pct) -Encoding ASCII
    } catch {}
}

function Get-WmiBrightnessRaw {
    try {
        $b = Get-CimInstance -Namespace root/WMI -ClassName WmiMonitorBrightness -ErrorAction Stop |
            Select-Object -First 1 -ExpandProperty CurrentBrightness
        if ($null -ne $b) { return [int]$b }
    } catch {}
    try {
        $b = (Get-WmiObject -Namespace root/WMI -Class WmiMonitorBrightness -ErrorAction Stop |
            Select-Object -First 1).CurrentBrightness
        if ($null -ne $b) { return [int]$b }
    } catch {}
    return $null
}

function Get-CurrentBrightness {
    $virt = Read-VirtualBrightness
    $wmi = Get-WmiBrightnessRaw
    if ($null -ne $wmi) {
        if ([Math]::Abs([int]$wmi - $virt) -le 8) { return [int]$wmi }
    }
    return $virt
}

# Low end: use exact % (10 must be darker than 20). Mid/high: mild stretch.
function Get-WmiHardwareTarget([int]$UserPct) {
    $u = [Math]::Max(0, [Math]::Min(100, $UserPct))
    if ($u -le 20) {
        # Exact backlight for 10/20 - remap used to push 10->24 and looked "broken".
        return [Math]::Max(5, $u)
    }
    $t = $u / 100.0
    $hw = [int][Math]::Round(100.0 * [Math]::Pow($t, 0.75))
    if ($hw -lt 20) { $hw = 20 }
    return [Math]::Max(0, [Math]::Min(100, $hw))
}

$Percent = 50
if ($Value -match '^rel([+-]\d+)$') {
    $delta = [int]$Matches[1]
    $Percent = [Math]::Max(0, [Math]::Min(100, (Get-CurrentBrightness) + $delta))
} elseif ($Value -match '^\d+$') {
    $Percent = [int]$Value
} else {
    Write-Error "Bad brightness value: $Value"
    exit 1
}

if ($Percent -lt 0) { $Percent = 0 }
if ($Percent -gt 100) { $Percent = 100 }

function Test-SetWmiVerified([int]$Target) {
    $before = Get-WmiBrightnessRaw
    if ($null -eq $before) { return $false }

    $want = [Math]::Max(0, [Math]::Min(100, $Target))
    try {
        $methods = Get-CimInstance -Namespace root/WMI -ClassName WmiMonitorBrightnessMethods -ErrorAction Stop |
            Select-Object -First 1
        if (-not $methods) { return $false }
        $methods.WmiSetBrightness(1, $want) | Out-Null
    } catch {
        try {
            $methods = Get-WmiObject -Namespace root/WMI -Class WmiMonitorBrightnessMethods -ErrorAction Stop |
                Select-Object -First 1
            if (-not $methods) { return $false }
            $methods.WmiSetBrightness(1, $want) | Out-Null
        } catch { return $false }
    }

    Start-Sleep -Milliseconds 80
    $after = Get-WmiBrightnessRaw
    if ($null -eq $after) { return $false }
    return ([Math]::Abs([int]$after - $want) -le 8)
}

function Test-SetDdcVerified([int]$Target) {
    try {
        if (-not ("JarvisBrightDdc4" -as [type])) {
            Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class JarvisBrightDdc4 {
  public delegate bool MonitorEnumProc(IntPtr hMonitor, IntPtr hdcMonitor, ref RECT lprcMonitor, IntPtr dwData);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Auto)]
  public struct PHYSICAL_MONITOR {
    public IntPtr hPhysicalMonitor;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string szPhysicalMonitorDescription;
  }
  [DllImport("user32.dll")] public static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr lprcClip, MonitorEnumProc lpfnEnum, IntPtr dwData);
  [DllImport("dxva2.dll", SetLastError=true)] public static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR(IntPtr hMonitor, ref uint pdwNumberOfPhysicalMonitors);
  [DllImport("dxva2.dll", SetLastError=true)] public static extern bool GetPhysicalMonitorsFromHMONITOR(IntPtr hMonitor, uint dwPhysicalMonitorArraySize, [Out] PHYSICAL_MONITOR[] pPhysicalMonitorArray);
  [DllImport("dxva2.dll", SetLastError=true)] public static extern bool SetMonitorBrightness(IntPtr hMonitor, uint dwNewBrightness);
  [DllImport("dxva2.dll", SetLastError=true)] public static extern bool GetMonitorBrightness(IntPtr hMonitor, ref uint pdwMinimumBrightness, ref uint pdwCurrentBrightness, ref uint pdwMaximumBrightness);
  [DllImport("dxva2.dll", SetLastError=true)] public static extern bool DestroyPhysicalMonitors(uint dwPhysicalMonitorArraySize, PHYSICAL_MONITOR[] pPhysicalMonitorArray);
  private static List<IntPtr> _mons = new List<IntPtr>();
  private static bool EnumCb(IntPtr hMonitor, IntPtr hdcMonitor, ref RECT lprcMonitor, IntPtr dwData) {
    _mons.Add(hMonitor); return true;
  }
  public static bool TrySet(uint pct) {
    _mons.Clear();
    EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, EnumCb, IntPtr.Zero);
    bool any = false;
    foreach (IntPtr hmon in _mons) {
      uint count = 0;
      if (!GetNumberOfPhysicalMonitorsFromHMONITOR(hmon, ref count) || count == 0) continue;
      PHYSICAL_MONITOR[] arr = new PHYSICAL_MONITOR[count];
      if (!GetPhysicalMonitorsFromHMONITOR(hmon, count, arr)) continue;
      for (int i = 0; i < arr.Length; i++) {
        IntPtr ph = arr[i].hPhysicalMonitor;
        uint min=0, cur=0, max=0;
        if (!GetMonitorBrightness(ph, ref min, ref cur, ref max) || max <= min) continue;
        uint val = min + (uint)((max - min) * Math.Min(100, Math.Max(0, (int)pct)) / 100.0);
        if (!SetMonitorBrightness(ph, val)) continue;
        System.Threading.Thread.Sleep(60);
        min=0; cur=0; max=0;
        if (!GetMonitorBrightness(ph, ref min, ref cur, ref max) || max <= min) continue;
        uint expect = min + (uint)((max - min) * Math.Min(100, Math.Max(0, (int)pct)) / 100.0);
        long span = Math.Max(1, (long)max - (long)min);
        if (Math.Abs((long)cur - (long)expect) <= Math.Max(2, span * 8 / 100)) any = true;
      }
      DestroyPhysicalMonitors(count, arr);
    }
    return any;
  }
}
"@ -ErrorAction Stop
        }
        return [JarvisBrightDdc4]::TrySet([uint32]$Target)
    } catch {
        return $false
    }
}

function Test-SetGammaAll([int]$Target) {
    try {
        if (-not ("JarvisGammaLin6" -as [type])) {
            Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class JarvisGammaLin6 {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  public struct DISPLAY_DEVICE {
    public int cb;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string DeviceName;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string DeviceString;
    public int StateFlags;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string DeviceID;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string DeviceKey;
  }
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Ansi)]
  public struct RAMP {
    [MarshalAs(UnmanagedType.ByValArray, SizeConst=256)] public ushort[] Red;
    [MarshalAs(UnmanagedType.ByValArray, SizeConst=256)] public ushort[] Green;
    [MarshalAs(UnmanagedType.ByValArray, SizeConst=256)] public ushort[] Blue;
  }
  public const int DISPLAY_DEVICE_ACTIVE = 0x00000001;
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern bool EnumDisplayDevices(string lpDevice, uint iDevNum, ref DISPLAY_DEVICE lpDisplayDevice, uint dwFlags);
  [DllImport("gdi32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr CreateDC(string lpszDriver, string lpszDevice, string lpszOutput, IntPtr lpInitData);
  [DllImport("gdi32.dll")] public static extern bool DeleteDC(IntPtr hdc);
  [DllImport("gdi32.dll")] public static extern bool SetDeviceGammaRamp(IntPtr hdc, ref RAMP lpRamp);
  [DllImport("user32.dll")] public static extern IntPtr GetDC(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);

  // Floor 0.50 - many GPUs reject darker ramps (10% used to fail silently).
  // 10->0.55, 20->0.60, 50->0.75, 100->1.0 so 10 is visibly darker than 20/50.
  static double ScaleFromPct(int pct) {
    if (pct < 0) pct = 0;
    if (pct > 100) pct = 100;
    return 0.50 + 0.50 * (pct / 100.0);
  }

  static ushort EncodeWord(int value, int mode) {
    if (value < 0) value = 0;
    if (value > 65535) value = 65535;
    if (mode == 1) {
      int hi = (value >> 8) & 0xFF;
      return (ushort)((hi << 8) | hi);
    }
    return (ushort)value;
  }

  static RAMP BuildRamp(int pct, int mode) {
    double scale = ScaleFromPct(pct);
    RAMP ramp = new RAMP();
    ramp.Red = new ushort[256];
    ramp.Green = new ushort[256];
    ramp.Blue = new ushort[256];
    for (int i = 0; i < 256; i++) {
      int raw = (int)Math.Round(i * 257.0 * scale);
      ushort w = EncodeWord(raw, mode);
      ramp.Red[i] = w; ramp.Green[i] = w; ramp.Blue[i] = w;
    }
    for (int i = 1; i < 256; i++) {
      if (ramp.Red[i] < ramp.Red[i - 1]) {
        ramp.Red[i] = ramp.Red[i - 1];
        ramp.Green[i] = ramp.Green[i - 1];
        ramp.Blue[i] = ramp.Blue[i - 1];
      }
    }
    return ramp;
  }

  static bool ApplyRamp(ref RAMP ramp) {
    bool any = false;
    IntPtr screen = GetDC(IntPtr.Zero);
    if (screen != IntPtr.Zero) {
      if (SetDeviceGammaRamp(screen, ref ramp)) any = true;
      ReleaseDC(IntPtr.Zero, screen);
    }
    for (uint idx = 0; ; idx++) {
      DISPLAY_DEVICE dd = new DISPLAY_DEVICE();
      dd.cb = Marshal.SizeOf(typeof(DISPLAY_DEVICE));
      if (!EnumDisplayDevices(null, idx, ref dd, 0)) break;
      if ((dd.StateFlags & DISPLAY_DEVICE_ACTIVE) == 0) continue;
      IntPtr hdc = CreateDC("DISPLAY", dd.DeviceName, null, IntPtr.Zero);
      if (hdc == IntPtr.Zero) continue;
      if (SetDeviceGammaRamp(hdc, ref ramp)) any = true;
      DeleteDC(hdc);
    }
    return any;
  }

  public static bool Set(int pct) {
    for (int mode = 0; mode <= 2; mode++) {
      RAMP ramp = BuildRamp(pct, mode);
      if (ApplyRamp(ref ramp)) return true;
    }
    return false;
  }
}
"@ -ErrorAction Stop
        }
        return [JarvisGammaLin6]::Set($Target)
    } catch {
        return $false
    }
}

$how = @()
$gammaAssistOk = $false

# 1) DDC/CI - external monitors (true hardware brightness)
$ddcOk = Test-SetDdcVerified $Percent
if ($ddcOk) {
    $how += "DDC"
    # Clear any leftover software dim from a previous laptop session.
    [void](Test-SetGammaAll 100)
}

# 2) WMI - laptop panels
$wmiOk = $false
if (-not $ddcOk) {
    $hw = Get-WmiHardwareTarget $Percent
    $wmiOk = Test-SetWmiVerified $hw
    if ($wmiOk) {
        $how += ("WMI{0}" -f $hw)
    }
    # Always assist with gamma below 95% (10% must dim even if WMI alone looks flat).
    if ($Percent -ge 95) {
        [void](Test-SetGammaAll 100)
    } else {
        $gOk = Test-SetGammaAll $Percent
        if (-not $gOk -and $Percent -le 15) {
            Start-Sleep -Milliseconds 50
            $gOk = Test-SetGammaAll $Percent
        }
        if ($gOk) {
            $how += "GAMMA"
            $gammaAssistOk = $true
        }
    }
}

# 3) Gamma-only when no hardware path
$gammaOk = $false
if (-not $ddcOk -and -not $wmiOk -and -not $gammaAssistOk) {
    $gammaOk = Test-SetGammaAll $Percent
    if ($gammaOk) { $how += "GAMMA" }
}

if ($ddcOk -or $wmiOk -or $gammaOk -or $gammaAssistOk) {
    Save-VirtualBrightness $Percent
    Write-Host ("JARVIS brightness {0}% via {1}" -f $Percent, ($how -join "+"))
    exit 0
}

if (Test-SetGammaAll $Percent) {
    Save-VirtualBrightness $Percent
    Write-Host "JARVIS brightness $Percent% via GAMMA"
    exit 0
}

Save-VirtualBrightness $Percent
Write-Host "JARVIS brightness $Percent% via VIRTUAL (display API unavailable)"
exit 0
