-- Random image from Pictures / JARVIS folders → desktop wallpaper.
jarvis.system.exec("powershell", {
  "-NoProfile",
  "-STA",
  "-ExecutionPolicy",
  "Bypass",
  "-File",
  "resources/scripts/set-wallpaper.ps1",
  "random",
})
return { chain = false }
