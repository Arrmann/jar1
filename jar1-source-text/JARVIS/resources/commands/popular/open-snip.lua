jarvis.system.exec("powershell", {
  "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
  "resources/scripts/open-known-app.ps1", "snip",
})
return { chain = false }
