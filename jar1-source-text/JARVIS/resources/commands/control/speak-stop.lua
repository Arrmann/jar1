-- Stop Silero TTS playback (flags + kill hosts). Esc in the app does the same.
jarvis.system.exec("powershell", {
  "-NoProfile",
  "-STA",
  "-ExecutionPolicy",
  "Bypass",
  "-File",
  "resources/scripts/tts-stop.ps1",
})

jarvis.system.notify("Озвучка", "Чтение остановлено")
return { chain = false }
