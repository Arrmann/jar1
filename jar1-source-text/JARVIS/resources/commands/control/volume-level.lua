-- Absolute volume from command id volume_0 .. volume_100 via proven set-volume.ps1
local id = tostring(jarvis.context.command_id or "")
local pct = tonumber(id:match("volume_(%d+)"))
if not pct then
  local phrase = (jarvis.context.phrase or ""):lower()
  local num = phrase:match("(%d+)")
  pct = num and tonumber(num) or 50
end
if pct < 0 then pct = 0 end
if pct > 100 then pct = 100 end

jarvis.system.exec("powershell", {
  "-NoProfile", "-ExecutionPolicy", "Bypass",
  "-File", "resources/scripts/set-volume.ps1", tostring(pct),
})
return { chain = false }
