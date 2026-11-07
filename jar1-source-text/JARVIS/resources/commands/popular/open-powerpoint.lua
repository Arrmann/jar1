jarvis.system.exec("powershell", {
  "-NoProfile", "-Command",
  "try { Start-Process powerpnt -ErrorAction Stop } catch { & 'resources/scripts/open-url.ps1' 'https://www.office.com' }",
})
return { chain = false }
