jarvis.system.exec("powershell", {
  "-NoProfile",
  "-ExecutionPolicy",
  "Bypass",
  "-File",
  "resources/scripts/close-active.ps1",
})
return { chain = false }
