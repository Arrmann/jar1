jarvis.system.exec("powershell", {
  "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
  "resources/scripts/set-preferred-browser.ps1", "yandex",
})
return { chain = false }
