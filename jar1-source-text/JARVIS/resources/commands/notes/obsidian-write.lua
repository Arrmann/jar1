-- «запиши в заметки …» → session dictation into one Inbox/*.md draft
local phrase = jarvis.context.phrase or ""
local r = jarvis.obsidian.dictate_from_phrase(phrase)

if r.error == "no_vault" then
  jarvis.system.notify("Заметки", "Укажи папку Obsidian в настройках")
  return { chain = false, silent = true }
end

if r.error == "io" then
  jarvis.system.notify("Заметки", "Не удалось создать черновик")
  return { chain = false, silent = true }
end

if r.ok and r.started then
  jarvis.pending.set("note_dictate")
  if r.appended then
    jarvis.system.notify("Заметки", "Пишу. Скажи «закончи» когда готово")
  else
    jarvis.system.notify("Заметки", "Диктуй. Скажи «закончи» когда готово")
  end
  if type(r.path) == "string" and r.path ~= "" then
    jarvis.log("info", "obsidian_dictate start -> " .. r.path)
  end
  return { chain = true, silent = true }
end

jarvis.system.notify("Заметки", "Не удалось начать диктовку")
return { chain = false, silent = true }
