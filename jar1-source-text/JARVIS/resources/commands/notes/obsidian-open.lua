-- «открой заметку …»
local phrase = jarvis.context.phrase or ""
local r = jarvis.obsidian.open(phrase)

if r.need_text then
  jarvis.system.notify("Заметки", "Скажи название заметки")
  return { chain = false, silent = true }
end

if r.ok then
  jarvis.system.notify("Заметки", "Открываю")
  return { chain = false, silent = false }
end

if r.error == "no_vault" then
  jarvis.system.notify("Заметки", "Укажи папку Obsidian в настройках")
elseif r.error == "not_found" then
  jarvis.system.notify("Заметки", "Заметка не найдена")
else
  jarvis.system.notify("Заметки", "Не удалось открыть")
end
return { chain = false, silent = true }
