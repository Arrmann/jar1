jarvis.system.exec("powershell", {
  "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
  "resources/scripts/browser-control.ps1", "next_tab",
})
return { chain = false }
