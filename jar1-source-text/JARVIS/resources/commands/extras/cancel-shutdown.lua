-- Cancel pending power-off / reboot AND reminders/timers/TTS/LED timer.
jarvis.schedule.shutdown_cancel()
jarvis.schedule.cancel_all()

pcall(function()
  jarvis.system.run_python("resources/scripts/led-strip-ble.py", { "timer_cancel" })
end)

pcall(function()
  jarvis.system.exec("powershell", {
    "-NoProfile",
    "-STA",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    "resources/scripts/tts-stop.ps1",
  })
end)

jarvis.system.notify("Отмена", "Выключение / таймеры / озвучка отменены")
return { chain = false }
