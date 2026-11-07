-- Proven OS minimize (last-target / yield JARVIS). Fire-and-forget — no voice wait on PS.
jarvis.system.exec("powershell", {
  "-NoProfile", "-ExecutionPolicy", "Bypass",
  "-File", "resources/scripts/window-size.ps1", "min",
})
return { chain = false }
