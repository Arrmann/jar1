-- Stop continuous native dictation.
jarvis.system.exec("powershell", {
  "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
  "resources/scripts/dictate-control.ps1", "stop",
})
jarvis.system.notify("Диктовка", "Остановлено")
return { chain = false }
