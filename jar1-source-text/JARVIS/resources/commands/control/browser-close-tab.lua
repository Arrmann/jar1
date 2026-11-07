-- Fire-and-forget: closing a tab is instant; do not block the voice pipeline.
jarvis.system.exec("powershell", {
  "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
  "resources/scripts/browser-control.ps1", "close_tab",
})
return { chain = false }
