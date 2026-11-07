-- Cancel all pending reminders and timers
pcall(function()
  jarvis.schedule.cancel_all()
end)

jarvis.system.notify("Отмена", "Таймеры и напоминания отменены")
return { chain = false }
