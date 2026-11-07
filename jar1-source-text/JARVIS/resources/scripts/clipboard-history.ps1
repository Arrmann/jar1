Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class JarvisKeys {
  [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
}
"@

$KEYEVENTF_KEYUP = 2
$VK_LWIN = 0x5B
$VK_V = 0x56

[JarvisKeys]::keybd_event($VK_LWIN, 0, 0, [UIntPtr]::Zero)
[JarvisKeys]::keybd_event($VK_V, 0, 0, [UIntPtr]::Zero)
[JarvisKeys]::keybd_event($VK_V, 0, $KEYEVENTF_KEYUP, [UIntPtr]::Zero)
[JarvisKeys]::keybd_event($VK_LWIN, 0, $KEYEVENTF_KEYUP, [UIntPtr]::Zero)
