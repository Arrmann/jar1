jarvis.system.exec("powershell", {
  "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
  "resources/scripts/open-uri.ps1", "ms-settings:windowsupdate",
})
return { chain = false }
