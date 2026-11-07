-- Open preferred browser / google; no chaining while personal reply plays
jarvis.system.exec("powershell", {
  "-NoProfile",
  "-ExecutionPolicy",
  "Bypass",
  "-File",
  "resources/scripts/open-url.ps1",
  "https://www.google.com",
})
return { chain = false }
