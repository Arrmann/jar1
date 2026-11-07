jarvis.system.exec("powershell", {
  "-NoProfile", "-Command",
  "Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue; Start-Process explorer",
})
return { chain = false }
