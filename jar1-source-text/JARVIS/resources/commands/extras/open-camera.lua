jarvis.system.exec("powershell", {
  "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
  "resources/scripts/open-uri.ps1", "microsoft.windows.camera:",
})
return { chain = false }
