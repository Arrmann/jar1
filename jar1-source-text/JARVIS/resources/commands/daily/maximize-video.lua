-- YouTube expand: OS maximize + player fullscreen via window-size.ps1 video
jarvis.system.exec("powershell", {
  "-NoProfile", "-ExecutionPolicy", "Bypass",
  "-File", "resources/scripts/window-size.ps1", "video",
})
return { chain = false }
