-- Add a task from the spoken remainder: «добавь задачу купить молоко».
local phrase = jarvis.context.phrase or ""
local r = jarvis.tasks.add_from_phrase(phrase)

if r.need_text then
  jarvis.pending.set("task")
  jarvis.system.notify("Задачи", "Скажи задачу")
  return { chain = true, silent = true }
end

jarvis.pending.clear()

if r.ok then
  jarvis.system.notify("Задачи", "Задача добавлена")
  return { chain = false, silent = false }
end

if r.error == "full" then
  jarvis.system.notify("Задачи", "Уже 30 задач. Удали одну.")
elseif r.error == "io" then
  jarvis.system.notify("Задачи", "Не удалось сохранить задачу")
else
  jarvis.system.notify("Задачи", "Не понял задачу")
end
return { chain = false, silent = true }
