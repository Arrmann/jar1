-- LED effect speed (remote SPEED +/-).
local phrase = (jarvis.context.phrase or ""):lower()

local val = "50"
if phrase:find("быстр", 1, true) or phrase:find("faster", 1, true) then
  val = "faster"
elseif phrase:find("медлен", 1, true) or phrase:find("slower", 1, true) then
  val = "slower"
elseif phrase:find("макс", 1, true) then
  val = "100"
elseif phrase:find("мин", 1, true) then
  val = "5"
else
  local num = phrase:match("(%d+)")
  if num then val = num end
end

jarvis.system.run_python("resources/scripts/led-strip-ble.py", { "speed", val })
return { chain = false }
