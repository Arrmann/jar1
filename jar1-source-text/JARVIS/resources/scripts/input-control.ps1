param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet(
        "copy", "paste", "cut", "select_all", "undo", "redo",
        "delete_word", "delete_line", "enter", "escape", "tab",
        "save", "new", "print", "find", "home", "end", "page_up", "page_down",
        "switch_lang"
    )]
    [string]$Action
)

$ErrorActionPreference = "Stop"

if (-not ("JarvisInputKeys" -as [type])) {
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Threading;
public static class JarvisInputKeys {
  [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
  public const uint KEYEVENTF_KEYUP = 0x0002;
  public const byte VK_CONTROL = 0x11;
  public const byte VK_SHIFT = 0x10;
  public const byte VK_MENU = 0x12;
  public const byte VK_SPACE = 0x20;
  public const byte VK_BACK = 0x08;
  public const byte VK_DELETE = 0x2E;
  public const byte VK_RETURN = 0x0D;
  public const byte VK_ESCAPE = 0x1B;
  public const byte VK_TAB = 0x09;
  public const byte VK_HOME = 0x24;
  public const byte VK_END = 0x23;
  public const byte VK_PRIOR = 0x21;
  public const byte VK_NEXT = 0x22;
  public const byte VK_C = 0x43;
  public const byte VK_V = 0x56;
  public const byte VK_X = 0x58;
  public const byte VK_A = 0x41;
  public const byte VK_Z = 0x5A;
  public const byte VK_Y = 0x59;
  public const byte VK_S = 0x53;
  public const byte VK_N = 0x4E;
  public const byte VK_P = 0x50;
  public const byte VK_F = 0x46;

  static void Down(byte vk) { keybd_event(vk, 0, 0, UIntPtr.Zero); }
  static void Up(byte vk) { keybd_event(vk, 0, KEYEVENTF_KEYUP, UIntPtr.Zero); }
  public static void Tap(byte vk) { Down(vk); Up(vk); }
  public static void Chord(params byte[] keys) {
    foreach (var k in keys) Down(k);
    for (int i = keys.Length - 1; i >= 0; i--) Up(keys[i]);
  }
}
"@
}

Start-Sleep -Milliseconds 40

switch ($Action) {
    "copy" { [JarvisInputKeys]::Chord(0x11, 0x43) }
    "paste" { [JarvisInputKeys]::Chord(0x11, 0x56) }
    "cut" { [JarvisInputKeys]::Chord(0x11, 0x58) }
    "select_all" { [JarvisInputKeys]::Chord(0x11, 0x41) }
    "undo" { [JarvisInputKeys]::Chord(0x11, 0x5A) }
    "redo" { [JarvisInputKeys]::Chord(0x11, 0x59) }
    "delete_word" { [JarvisInputKeys]::Chord(0x11, 0x08) }
    "delete_line" {
        [JarvisInputKeys]::Tap(0x24) # HOME
        [JarvisInputKeys]::Chord(0x10, 0x23) # SHIFT+END
        [JarvisInputKeys]::Tap(0x2E) # DEL
    }
    "enter" { [JarvisInputKeys]::Tap(0x0D) }
    "escape" { [JarvisInputKeys]::Tap(0x1B) }
    "tab" { [JarvisInputKeys]::Tap(0x09) }
    "save" { [JarvisInputKeys]::Chord(0x11, 0x53) }
    "new" { [JarvisInputKeys]::Chord(0x11, 0x4E) }
    "print" { [JarvisInputKeys]::Chord(0x11, 0x50) }
    "find" { [JarvisInputKeys]::Chord(0x11, 0x46) }
    "home" { [JarvisInputKeys]::Tap(0x24) }
    "end" { [JarvisInputKeys]::Tap(0x23) }
    "page_up" { [JarvisInputKeys]::Tap(0x21) }
    "page_down" { [JarvisInputKeys]::Tap(0x22) }
    "switch_lang" { [JarvisInputKeys]::Chord(0x12, 0x10) } # Alt+Shift
}

Write-Host "JARVIS input-control: $Action"
exit 0
