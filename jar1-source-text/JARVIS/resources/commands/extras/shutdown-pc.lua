-- PC shutdown: immediate (60s grace) OR delayed from "через N секунд/минут/часов".
local phrase = (jarvis.context.phrase or ""):lower()

local delayed = phrase:find("через", 1, true)
  or phrase:find("таймер выключения", 1, true)
  or phrase:find("отложи", 1, true)
  or phrase:find("shutdown in", 1, true)
  or phrase:find("power off in", 1, true)

if delayed then
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
  jarvis.system.notify("Выключение", result.error or "Не понял время")
  return { chain = false, silent = true }
end

-- No delay in phrase → 60 second grace (cancel: «отмени выключение»)
local result = jarvis.schedule.shutdown({ seconds = 60 })
if result.ok then
  jarvis.system.notify("Выключение", "Через 60 сек. Скажи «отмени выключение» чтобы отменить")
  return { chain = false, silent = false }
end

jarvis.system.notify("Выключение", result.error or "Не удалось поставить таймер")
return { chain = false, silent = true }
