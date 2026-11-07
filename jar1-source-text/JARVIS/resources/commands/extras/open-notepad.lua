jarvis.system.exec("powershell", {
  "-NoProfile", "-ExecutionPolicy", "Bypass",
  "-File", "resources/scripts/open-process.ps1", "notepad",
})
return { chain = false }
