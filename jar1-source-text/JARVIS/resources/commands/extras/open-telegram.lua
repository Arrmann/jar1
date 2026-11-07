-- Open Telegram Desktop by exe path; protocol / web only as fallback.
jarvis.system.exec("powershell", {
  "-NoProfile",
  "-ExecutionPolicy",
  "Bypass",
  "-File",
  "resources/scripts/open-known-app.ps1",
  "telegram",
})
return { chain = false }
