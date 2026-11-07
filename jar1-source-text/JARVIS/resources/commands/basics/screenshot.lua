jarvis.system.exec("powershell", {
  "-NoProfile",
  "-STA",
  "-ExecutionPolicy",
  "Bypass",
  "-File",
  "resources/scripts/screenshot.ps1",
})
return { chain = false }
