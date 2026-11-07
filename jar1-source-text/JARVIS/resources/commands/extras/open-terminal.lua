jarvis.system.exec("powershell", {
  "-NoProfile",
  "-Command",
  "if (Get-Command wt -ErrorAction SilentlyContinue) { Start-Process wt } else { Start-Process cmd }",
})
return { chain = false }
