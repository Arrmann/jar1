-- YouTube: exit player fullscreen only (window stays open / maximized).
jarvis.system.exec("powershell", {
  "-NoProfile", "-ExecutionPolicy", "Bypass",
  "-File", "resources/scripts/window-size.ps1", "video_exit",
})
return { chain = false }
