-- Latest JARVIS screenshot → desktop wallpaper.
jarvis.system.exec("powershell", {
  "-NoProfile",
  "-STA",
  "-ExecutionPolicy",
  "Bypass",
  "-File",
  "resources/scripts/set-wallpaper.ps1",
  "latest-screenshot",
})
return { chain = false }
