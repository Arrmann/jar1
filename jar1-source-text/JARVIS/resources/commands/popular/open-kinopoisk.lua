jarvis.system.exec("powershell", {
  "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
  "resources/scripts/open-url.ps1", "https://www.kinopoisk.ru",
})
return { chain = false }
