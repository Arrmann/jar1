-- Delayed PC power-off (native schedule — no cmd flash).
local phrase = (jarvis.context.phrase or ""):lower()

local result = jarvis.schedule.shutdown({ phrase = phrase })
if result.ok then
  local label = result.label or ""
  if label ~= "" then
    jarvis.system.notify("Выключение", "Через " .. label)
  else
    jarvis.system.notify("Выключение", "Таймер поставлен")
  end
  return { chain = false, silent = false }
end

jarvis.system.notify("Выключение", result.error or "Не понял время. Пример: выключи через 10 минут")
return { chain = false, silent = true }
