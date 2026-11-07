jarvis.system.exec("powershell", {
  "-NoProfile", "-ExecutionPolicy", "Bypass",
  "-Command",
  ". 'resources/scripts/audio-core.ps1'; try { [JarvisCoreAudio.Volume]::SetMuted($true) } catch { [JarvisCoreAudio.Volume]::MuteByKey() }",
})
return { chain = false }
