-- Set volume from spoken percent: "громкость 50", "звук на 30"
local phrase = (jarvis.context.phrase or ""):lower()

local map = {
  ["ноль"] = 0, ["нуль"] = 0,
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
  jarvis.system.notify("Громкость", "Скажите например: громкость 50")
  return { chain = true }
end

if pct ~= 0 and pct < 10 then pct = 10 end
if pct > 100 then pct = 100 end

jarvis.system.exec("powershell", {
  "-NoProfile", "-ExecutionPolicy", "Bypass",
  "-File", "resources/scripts/set-volume.ps1", tostring(pct),
})
return { chain = false }
