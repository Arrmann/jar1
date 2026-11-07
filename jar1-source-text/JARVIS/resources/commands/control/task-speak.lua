-- Speak the task list with the same engine TTS path as clipboard «озвучь».
local enabled = tostring(jarvis.settings.get("tts_enabled") or "")
enabled = string.lower(enabled)
if enabled == "false" or enabled == "0" or enabled == "off" then
  jarvis.system.notify("Задачи", "Озвучка выключена в настройках")
  return { chain = false, silent = true }
end

local text = jarvis.tasks.speak_text()
if text == nil or text == "" then
  text = "Задач нет."
end

local ok, err = pcall(function()
  jarvis.speak(text)
end)
if not ok then
  jarvis.log("error", "task_speak failed: " .. tostring(err))
  jarvis.system.notify("Задачи", "Не удалось озвучить")
end
return { chain = false, silent = true }
