-- «добавь в ежедневную …» → Daily/YYYY-MM-DD.md
local phrase = jarvis.context.phrase or ""
local r = jarvis.obsidian.daily_from_phrase(phrase)

if r.need_text then
  jarvis.pending.set("note_daily")
  jarvis.system.notify("Заметки", "Скажи текст для дневника")
  return { chain = true, silent = true }
end

jarvis.pending.clear()

if r.ok then
  jarvis.system.notify("Заметки", "Добавлено в ежедневную")
  return { chain = false, silent = false }
end

if r.error == "no_vault" then
  jarvis.system.notify("Заметки", "Укажи папку Obsidian в настройках")
else
  jarvis.system.notify("Заметки", "Не удалось дописать дневник")
end
return { chain = false, silent = true }
