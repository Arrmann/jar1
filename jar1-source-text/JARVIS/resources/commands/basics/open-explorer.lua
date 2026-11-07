-- Fire-and-forget: don't block voice on PowerShell cold start / explorer settle.
jarvis.system.exec("powershell", {
  "-NoProfile", "-ExecutionPolicy", "Bypass",
  "-File", "resources/scripts/open-folder.ps1",
  "-Known", "home",
})
return { chain = false }
