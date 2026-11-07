jarvis.system.exec("powershell", {
  "-NoProfile", "-Command",
  "try { Start-Process 'msteams:' -ErrorAction Stop } catch { & 'resources/scripts/open-url.ps1' 'https://teams.microsoft.com' }",
})
return { chain = false }
