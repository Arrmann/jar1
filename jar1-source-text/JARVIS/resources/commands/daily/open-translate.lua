jarvis.system.exec("powershell", {
  "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
  "resources/scripts/open-url.ps1",
  "https://translate.google.com/?sl=auto&tl=ru",
})
return { chain = false }
