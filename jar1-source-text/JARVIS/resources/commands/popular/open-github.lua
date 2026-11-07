jarvis.system.exec("powershell", {
  "-NoProfile", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass", "-File",
  "resources/scripts/open-url.ps1", "https://github.com",
})
return { chain = false }
