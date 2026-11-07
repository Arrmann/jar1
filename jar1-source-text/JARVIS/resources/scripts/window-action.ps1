param([ValidateSet("minimize_window","close_window","close_all")][string]$Action)
$ErrorActionPreference="Stop"
. (Join-Path $PSScriptRoot "_jarvis-last-target.ps1")
Initialize-JarvisLastTarget
Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class JarvisWindowAction {
 public delegate bool Callback(IntPtr h,IntPtr p);
 [DllImport("user32.dll")] public static extern bool EnumWindows(Callback c,IntPtr p);
 [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);
 [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h,uint m,IntPtr w,IntPtr l);
 [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr h,int n);
 public static bool Eligible(IntPtr h) {
  if(!IsWindowVisible(h)) return false;
  var c=new StringBuilder(256);GetClassName(h,c,256);
  if(c.ToString()=="Shell_TrayWnd"||c.ToString()=="Progman"||c.ToString()=="WorkerW"||c.ToString()=="Shell_SecondaryTrayWnd")return false;
  uint pid;GetWindowThreadProcessId(h,out pid);
  try{var name=System.Diagnostics.Process.GetProcessById((int)pid).ProcessName;if(name.StartsWith("jarvis",StringComparison.OrdinalIgnoreCase)||name=="powershell"||name=="pwsh")return false;}catch{return false;}
  var text=new StringBuilder(512);return GetWindowText(h,text,512)>0;
 }
 public static void CloseAll(){var items=new List<IntPtr>();EnumWindows((h,p)=>{if(Eligible(h))items.Add(h);return true;},IntPtr.Zero);foreach(var h in items)PostMessage(h,0x10,IntPtr.Zero,IntPtr.Zero);}
}
"@
if($Action -eq "close_all"){[JarvisWindowAction]::CloseAll();exit 0}
$target=Resolve-JarvisControlHwnd
if($target -eq [IntPtr]::Zero -or -not [JarvisWindowAction]::Eligible($target)){throw "No application window"}
if($Action -eq "minimize_window"){[void][JarvisWindowAction]::ShowWindowAsync($target,7)}else{[void][JarvisWindowAction]::PostMessage($target,0x10,[IntPtr]::Zero,[IntPtr]::Zero)}
