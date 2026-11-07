# Shared audio helpers. Prefer Core Audio; fall back to keybd_event (more reliable than SendKeys).

if ("JarvisCoreAudio.Volume" -as [type]) { return }

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

namespace JarvisCoreAudio {
  [UnmanagedFunctionPointer(CallingConvention.Winapi)]
  public delegate int ActivateDelegate(IntPtr self, ref Guid iid, uint dwClsCtx, IntPtr pActivationParams, out IntPtr ppInterface);
  [UnmanagedFunctionPointer(CallingConvention.Winapi)]
  public delegate int SetMuteDelegate(IntPtr self, int muted, IntPtr eventContext);
  [UnmanagedFunctionPointer(CallingConvention.Winapi)]
  public delegate int SetVolumeScalarDelegate(IntPtr self, float level, IntPtr eventContext);
  [UnmanagedFunctionPointer(CallingConvention.Winapi)]
  public delegate int GetVolumeScalarDelegate(IntPtr self, out float level);
  [UnmanagedFunctionPointer(CallingConvention.Winapi)]
  public delegate int GetMuteDelegate(IntPtr self, out int muted);

  [Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  public interface IMMDeviceEnumerator {
    int EnumAudioEndpoints(int dataFlow, int dwStateMask, out IntPtr ppDevices);
    int GetDefaultAudioEndpoint(int dataFlow, int role, out IntPtr ppDevice);
  }

  [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
  public class MMDeviceEnumeratorComObject { }

  public static class NativeKeys {
    [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
    public const byte VK_VOLUME_MUTE = 0xAD;
    public const byte VK_VOLUME_DOWN = 0xAE;
    public const byte VK_VOLUME_UP = 0xAF;
    public const uint KEYEVENTF_KEYUP = 0x0002;

    public static void Tap(byte vk) {
      keybd_event(vk, 0, 0, UIntPtr.Zero);
      keybd_event(vk, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
    }
  }

  public static class Volume {
    static IntPtr GetEndpointPtr() {
      // Try all roles — some PCs expose EP volume only on console/communications.
      var enumerator = (IMMDeviceEnumerator)(new MMDeviceEnumeratorComObject());
      int[] roles = new int[] { 1, 0, 2 };
      Exception last = null;
      foreach (int role in roles) {
        IntPtr devicePtr = IntPtr.Zero;
        int hr = enumerator.GetDefaultAudioEndpoint(0, role, out devicePtr);
        if (hr != 0 || devicePtr == IntPtr.Zero) continue;
        try {
          IntPtr vtable = Marshal.ReadIntPtr(devicePtr);
          IntPtr activatePtr = Marshal.ReadIntPtr(vtable, IntPtr.Size * 3);
          ActivateDelegate activate = (ActivateDelegate)Marshal.GetDelegateForFunctionPointer(activatePtr, typeof(ActivateDelegate));
          Guid iid = new Guid("5CDF2C82-841E-4546-9722-0CF740782BA3");
          IntPtr epPtr;
          hr = activate(devicePtr, ref iid, 23, IntPtr.Zero, out epPtr);
          if (hr == 0 && epPtr != IntPtr.Zero) {
            Marshal.Release(devicePtr);
            return epPtr;
          }
          last = Marshal.GetExceptionForHR(hr);
        } finally {
          if (devicePtr != IntPtr.Zero) Marshal.Release(devicePtr);
        }
      }
      if (last != null) throw last;
      throw new InvalidOperationException("IAudioEndpointVolume not available on default render devices");
    }

    static T VTable<T>(IntPtr obj, int slot) where T : class {
      IntPtr vtable = Marshal.ReadIntPtr(obj);
      IntPtr fn = Marshal.ReadIntPtr(vtable, IntPtr.Size * slot);
      return (T)(object)Marshal.GetDelegateForFunctionPointer(fn, typeof(T));
    }

    public static float GetScalar() {
      IntPtr ep = GetEndpointPtr();
      try {
        var getVol = VTable<GetVolumeScalarDelegate>(ep, 9);
        float got;
        Marshal.ThrowExceptionForHR(getVol(ep, out got));
        return got;
      } finally {
        Marshal.Release(ep);
      }
    }

    public static float SetScalar(float level) {
      IntPtr ep = GetEndpointPtr();
      try {
        // IAudioEndpointVolume slots (incl. IUnknown 0..2):
        // 8 GetMasterVolumeLevelScalar, 9 SetMasterVolumeLevelScalar,
        // 14 GetMute, 15 SetMute
        var setMute = VTable<SetMuteDelegate>(ep, 15);
        var setVol = VTable<SetVolumeScalarDelegate>(ep, 9);
        var getVol = VTable<GetVolumeScalarDelegate>(ep, 8);
        Marshal.ThrowExceptionForHR(setMute(ep, 0, IntPtr.Zero));
        Marshal.ThrowExceptionForHR(setVol(ep, level, IntPtr.Zero));
        float got;
        Marshal.ThrowExceptionForHR(getVol(ep, out got));
        return got;
      } finally {
        Marshal.Release(ep);
      }
    }

    public static void SetMuted(bool muted) {
      IntPtr ep = GetEndpointPtr();
      try {
        var setMute = VTable<SetMuteDelegate>(ep, 15);
        Marshal.ThrowExceptionForHR(setMute(ep, muted ? 1 : 0, IntPtr.Zero));
      } finally {
        Marshal.Release(ep);
      }
    }

    public static bool GetMuted() {
      IntPtr ep = GetEndpointPtr();
      try {
        var getMute = VTable<GetMuteDelegate>(ep, 14);
        int muted;
        Marshal.ThrowExceptionForHR(getMute(ep, out muted));
        return muted != 0;
      } finally {
        Marshal.Release(ep);
      }
    }

    public static void SetScalarByKeys(int percent) {
      if (percent < 0) percent = 0;
      if (percent > 100) percent = 100;
      // ~2% per step on Windows
      for (int i = 0; i < 50; i++) NativeKeys.Tap(NativeKeys.VK_VOLUME_DOWN);
      int steps = (int)Math.Round(percent / 2.0);
      for (int i = 0; i < steps; i++) NativeKeys.Tap(NativeKeys.VK_VOLUME_UP);
    }

    public static void MuteByKey() {
      NativeKeys.Tap(NativeKeys.VK_VOLUME_MUTE);
    }
  }
}
"@
