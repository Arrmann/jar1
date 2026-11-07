-- Countdown timer: seconds / minutes / hours / days
local phrase = (jarvis.context.phrase or ""):lower()

local prefixes = {
  "поставь таймер на",
  "поставь таймер",
  "запусти таймер на",
  "запусти таймер",
  "таймер на",
  "таймер",
  "timer for",
  "set timer",
  "timer",
}

for _, prefix in ipairs(prefixes) do
  if phrase:sub(1, #prefix) == prefix then
    phrase = phrase:sub(#prefix + 1):gsub("^%s+", "")
    break
  end
end
phrase = phrase:gsub("^[%s,.:;-]+", ""):gsub("%s+$", "")

if phrase ~= "" and not phrase:find("через", 1, true)
    and not phrase:find("завтра", 1, true)
    and not phrase:find("послезавтра", 1, true) then
  phrase = "через " .. phrase
end

if phrase == "" or phrase == "через " then
  jarvis.pending.set("timer")
  jarvis.system.notify("Таймер", "Сколько? Например: 5 минут, 30 секунд, 2 часа")
  return { chain = true, silent = true }
end

jarvis.pending.clear()

local full = "таймер " .. phrase
local result = jarvis.schedule.set(full, "timer")

if result.ok then
  local msg = result.when or ""
  if result.left_sec and result.left_sec > 0 then
    msg = msg .. " (" .. tostring(result.left_sec) .. "s)"
  end
  if result.text and result.text ~= "" then
    msg = msg .. " — " .. result.text
  end
  jarvis.system.notify("Таймер поставлен", msg)
  return { chain = false, silent = false }
end

local err = result.error or "Не удалось поставить"
jarvis.pending.set("timer")
jarvis.system.notify("Таймер", err)
return { chain = true, silent = true }
