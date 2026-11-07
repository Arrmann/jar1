-- Open Yandex home, but disambiguate common "яндекс …" follow-ups
-- when the classifier picks this intent instead of a more specific command.
local phrase = (jarvis.context.phrase or ""):lower()

local function open_url(url, force_browser)
  local args = {
    "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
    "resources/scripts/open-url.ps1", url,
  }
  if force_browser then
    args[#args + 1] = "-ForceBrowser"
    args[#args + 1] = force_browser
  end
  jarvis.system.exec("powershell", args)
end

if phrase:find("карт", 1, true) or phrase:find("map", 1, true) then
  open_url("https://yandex.ru/maps", nil)
elseif phrase:find("диск", 1, true) or phrase:find("disk", 1, true) then
  open_url("https://disk.yandex.ru", nil)
else
  open_url("https://ya.ru", nil)
end

return { chain = false }
