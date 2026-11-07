jarvis.system.exec("powershell", {
  "-NoProfile",
  "-ExecutionPolicy",
  "Bypass",
  "-File",
  "resources/scripts/input-control.ps1",
  "switch_lang",
})
return { chain = false }
