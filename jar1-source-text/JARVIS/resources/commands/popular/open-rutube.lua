jarvis.system.exec("powershell", {
  "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
  "resources/scripts/open-url.ps1", "https://rutube.ru",
})
return { chain = false }
