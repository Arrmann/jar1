jarvis.system.exec("powershell", {
  "-NoProfile", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass", "-File",
  "resources/scripts/open-cursor.ps1",
})
return { chain = false }
