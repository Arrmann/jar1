-- Voice: switch Silero TTS mode (background / on-demand). Does NOT disable neural TTS.

local phrase = (jarvis.context.phrase or ""):lower()



local mode = "ondemand"

if phrase:find("фонов", 1, true) or phrase:find("быстр", 1, true)

    or phrase:find("background", 1, true) or phrase:find("fast", 1, true) then

  mode = "background"

elseif phrase:find("эконом", 1, true) or phrase:find("без нагруз", 1, true)

    or phrase:find("только во время", 1, true) or phrase:find("on demand", 1, true)

    or phrase:find("ondemand", 1, true) then

  mode = "ondemand"

end



jarvis.system.exec_wait("powershell", {

  "-NoProfile", "-ExecutionPolicy", "Bypass",

  "-File", "resources/scripts/set-tts-mode.ps1",

  mode,

})



local label = (mode == "background") and "фоновый (быстрый старт)" or "только во время озвучки"

jarvis.system.notify("Озвучка", "Режим: " .. label)

return { chain = false }

