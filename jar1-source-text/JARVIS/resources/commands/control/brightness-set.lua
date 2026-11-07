-- Set brightness from spoken percent: "яркость 50", "яркость на 30"
local phrase = (jarvis.context.phrase or ""):lower()

local map = {
  ["десять"] = 10,
  ["двадцать"] = 20,
  ["тридцать"] = 30,
  ["сорок"] = 40,
  ["пятьдесят"] = 50,
  ["шестьдесят"] = 60,
  ["семьдесят"] = 70,
  ["восемьдесят"] = 80,
  ["девяносто"] = 90,
  ["сто"] = 100,
  ["половину"] = 50, ["половина"] = 50,
  ["максимум"] = 100, ["макс"] = 100,
  ["минимум"] = 10, ["мин"] = 10,
}

local pct = nil
local num = phrase:match("(%d+)")
if num then
  pct = tonumber(num)
else
  for word, value in pairs(map) do
    if phrase:find(word, 1, true) then
      pct = value
      break
    end
  end
end

if not pct then
  jarvis.system.notify("Яркость", "Скажите например: яркость 50")
  return { chain = true }
end

if pct < 10 then pct = 10 end
if pct > 100 then pct = 100 end

jarvis.system.brightness_set(pct)
return { chain = false }
