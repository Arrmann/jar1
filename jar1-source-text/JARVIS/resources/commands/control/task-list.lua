-- Open the tasks HUD (same chrome as timers).
jarvis.system.exec("powershell", {
  "-NoProfile",
  "-STA",
  "-ExecutionPolicy",
  "Bypass",
  "-WindowStyle",
  "Hidden",
  "-File",
  "resources/scripts/task-list.ps1",
})
return { chain = false }
