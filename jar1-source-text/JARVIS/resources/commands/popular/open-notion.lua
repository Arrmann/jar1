jarvis.system.exec("powershell", {
  "-NoProfile", "-Command",
  "try { Start-Process 'notion:' -ErrorAction Stop } catch { & 'resources/scripts/open-url.ps1' 'https://www.notion.so' }",
})
return { chain = false }
