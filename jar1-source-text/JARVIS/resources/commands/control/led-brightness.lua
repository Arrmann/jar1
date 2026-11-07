-- LED brightness from spoken percent / relative (remote +/-).
local phrase = (jarvis.context.phrase or ""):lower()

local map = {
  ["десять"] = 10, ["двадцать"] = 20, ["тридцать"] = 30, ["сорок"] = 40,
  ["пятьдесят"] = 50, ["шестьдесят"] = 60, ["семьдесят"] = 70,
  ["восемьдесят"] = 80, ["девяносто"] = 90, ["сто"] = 100,
  ["половину"] = 50, ["половина"] = 50,
  ["максимум"] = 100, ["макс"] = 100, ["минимум"] = 10, ["мин"] = 10,
}

local arg = nil
local num = phrase:match("(%d+)")
if num then
  arg = num
else
  for word, value in pairs(map) do
    if phrase:find(word, 1, true) then
      arg = tostring(value)
      break
    end
  end
end

if not arg then
  if phrase:find("ярче", 1, true) then
    arg = "up"
  elseif phrase:find("тускл", 1, true) or phrase:find("темн", 1, true) then
    arg = "down"
  end
end

if not arg then
  jarvis.system.notify("LED", "Скажите: яркость ленты 50 / ярче / тусклее")
  return { chain = true }
end

jarvis.system.run_python("resources/scripts/led-strip-ble.py", { "brightness", arg })
return { chain = false }
