jarvis.system.exec("powershell", {
  "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
  "resources/scripts/browser-control.ps1", "downloads",
})
return { chain = false }
