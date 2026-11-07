-- Pick an image and set it as the desktop wallpaper.
jarvis.system.exec("powershell", {
  "-NoProfile",
  "-STA",
  "-ExecutionPolicy",
  "Bypass",
  "-File",
  "resources/scripts/set-wallpaper.ps1",
  "pick",
})
return { chain = false }
