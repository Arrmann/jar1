-- «найди в заметках …»
local phrase = jarvis.context.phrase or ""
local r = jarvis.obsidian.search(phrase)

if r.need_text then
  jarvis.system.notify("Заметки", "Скажи, что искать")
  return { chain = false, silent = true }
end

if r.error == "no_vault" then
  jarvis.system.notify("Заметки", "Укажи папку Obsidian в настройках")
  return { chain = false, silent = true }
end

if not r.ok or not r.count or r.count == 0 then
  jarvis.system.notify("Заметки", "Ничего не найдено")
  return { chain = false, silent = true }
end

local first = r.results[1]
local title = (first and first.title) or "заметка"
jarvis.system.notify("Заметки", "Найдено: " .. tostring(title))
if first and first.path and first.path ~= "" then
  local open_r = jarvis.obsidian.open_path(first.path)
  if not open_r.ok then
    jarvis.system.notify("Заметки", "Нашёл, но не открыл: " .. tostring(title))
  end
end
return { chain = false, silent = false }
