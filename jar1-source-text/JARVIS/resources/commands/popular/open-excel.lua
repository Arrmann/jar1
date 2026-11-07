jarvis.system.exec("powershell", {
  "-NoProfile", "-Command",
  "try { Start-Process excel -ErrorAction Stop } catch { & 'resources/scripts/open-url.ps1' 'https://www.office.com' }",
})
return { chain = false }
