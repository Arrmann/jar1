# Alt+Tab via keybd_event (more reliable than WScript.SendKeys)
param()
$ErrorActionPreference = "Stop"
if (-not ("JarvisAltTab" -as [type])) {
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Threading;
public static class JarvisAltTab {
  [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
  public const uint KEYEVENTF_KEYUP = 0x0002;
  public const byte VK_MENU = 0x12;
  public const byte VK_TAB = 0x09;
  public static void Switch() {
    keybd_event(VK_MENU, 0, 0, UIntPtr.Zero);
    Thread.Sleep(40);
    keybd_event(VK_TAB, 0, 0, UIntPtr.Zero);
    keybd_event(VK_TAB, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
    Thread.Sleep(80);
    keybd_event(VK_MENU, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
  }
}
"@
}
[JarvisAltTab]::Switch()
Write-Host "JARVIS switch-window: done"
exit 0
