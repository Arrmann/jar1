jarvis.system.exec("powershell", {
  "-NoProfile", "-ExecutionPolicy", "Bypass",
  "-File", "resources/scripts/open-folder.ps1",
  "-Known", "downloads",
})
return { chain = false }
