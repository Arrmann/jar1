jarvis.system.exec("powershell", {
  "-NoProfile",
  "-Command",
  "try { Start-Process 'whatsapp:' -ErrorAction Stop } catch { & 'resources/scripts/open-url.ps1' 'https://web.whatsapp.com' }",
})
return { chain = false }
