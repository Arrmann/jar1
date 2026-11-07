local result = jarvis.schedule.restart({ seconds = 60 })
if result.ok then
  jarvis.system.notify("Перезагрузка", "Через 60 сек. Скажи «отмени выключение» чтобы отменить")
else
  jarvis.system.notify("Перезагрузка", result.error or "Не удалось")
end
return { chain = false }
