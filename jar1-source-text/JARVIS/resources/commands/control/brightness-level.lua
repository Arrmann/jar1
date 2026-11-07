-- Absolute brightness from command id brightness_10 .. brightness_100 (native DDC, PS fallback).
local id = tostring(jarvis.context.command_id or "")
local pct = tonumber(id:match("brightness_(%d+)"))
if not pct then
  local phrase = (jarvis.context.phrase or ""):lower()
  local num = phrase:match("(%d+)")
  pct = num and tonumber(num) or 50
end
if pct < 10 then pct = 10 end
if pct > 100 then pct = 100 end

jarvis.system.brightness_set(pct)
return { chain = false }
