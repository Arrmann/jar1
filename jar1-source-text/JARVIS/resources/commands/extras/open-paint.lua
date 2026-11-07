-- Start Paint without blocking: voice reply must play immediately.
jarvis.system.exec("powershell", {
  "-NoProfile", "-ExecutionPolicy", "Bypass",
  "-File", "resources/scripts/open-process.ps1", "mspaint",
})
return { chain = false }
