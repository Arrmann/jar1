jarvis.system.exec("powershell", {
  "-NoProfile", "-Command",
  "try { Start-Process 'zoommtg://' -ErrorAction Stop } catch { & 'resources/scripts/open-url.ps1' 'https://zoom.us' }",
})
return { chain = false }
