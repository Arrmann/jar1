-- Clear the whole list. Voice only via explicit «стереть все задачи».
local r = jarvis.tasks.clear()
if r and r.ok == false then
  jarvis.system.notify("Задачи", "Не удалось очистить список")
  return { chain = false, silent = true }
end
local n = 0
if r and r.count then
  n = r.count
end
if n == 0 then
  jarvis.system.notify("Задачи", "Задач нет")
else
  jarvis.system.notify("Задачи", "Список задач очищен")
end
return { chain = false }
