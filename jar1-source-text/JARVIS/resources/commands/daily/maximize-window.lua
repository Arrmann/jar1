-- Proven OS maximize (last-target / yield JARVIS). Fire-and-forget — no voice wait on PS.
jarvis.system.exec("powershell", {
  "-NoProfile", "-ExecutionPolicy", "Bypass",
  "-File", "resources/scripts/window-size.ps1", "max",
})
return { chain = false }
