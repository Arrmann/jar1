jarvis.system.exec("powershell", {
  "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
  "resources/scripts/set-preferred-browser.ps1", "chrome",
})
return { chain = false }
