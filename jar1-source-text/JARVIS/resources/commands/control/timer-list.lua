-- Show interactive list of pending timers/reminders
jarvis.system.exec("powershell", {
  "-NoProfile",
  "-STA",
  "-ExecutionPolicy",
  "Bypass",
  "-WindowStyle",
  "Hidden",
  "-File",
  "resources/scripts/timer-list.ps1",
})
return { chain = false }
