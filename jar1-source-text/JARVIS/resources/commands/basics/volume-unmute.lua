jarvis.system.exec("powershell", {
  "-NoProfile", "-ExecutionPolicy", "Bypass",
  "-Command",
  ". 'resources/scripts/audio-core.ps1'; try { [JarvisCoreAudio.Volume]::SetMuted($false) } catch { [JarvisCoreAudio.NativeKeys]::Tap([JarvisCoreAudio.NativeKeys]::VK_VOLUME_UP); [JarvisCoreAudio.NativeKeys]::Tap([JarvisCoreAudio.NativeKeys]::VK_VOLUME_DOWN) }",
})
return { chain = false }
