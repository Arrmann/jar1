-- Schedule a reminder from natural speech.
local phrase = (jarvis.context.phrase or ""):lower()

local prefixes = {
  "напомни мне",
  "напомни",
  "поставь напоминание",
  "напоминание",
  "remind me",
  "remind",
}

for _, prefix in ipairs(prefixes) do
  if phrase:sub(1, #prefix) == prefix then
    phrase = phrase:sub(#prefix + 1):gsub("^%s+", "")
    break
  end
end
phrase = phrase:gsub("^[%s,.:;-]+", ""):gsub("%s+$", "")

if phrase == "" then
  jarvis.pending.set("reminder")
  jarvis.system.notify("Напоминание", "Скажите: … через 10 минут / в 15 30 / завтра")
  return { chain = true, silent = true }
end

jarvis.pending.clear()

local result = jarvis.schedule.set(phrase, "reminder")

if result.ok then
  local msg = (result.when or "") .. (result.text and (" — " .. result.text) or "")
  jarvis.system.notify("Напоминание поставлено", msg)
  return { chain = false, silent = false }
end

local err = result.error or "Не удалось поставить"
jarvis.pending.set("reminder")
jarvis.system.notify("Напоминание", err)
jarvis.speak(err)
return { chain = true, silent = true }
