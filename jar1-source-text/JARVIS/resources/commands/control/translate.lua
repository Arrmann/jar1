-- Translate clipboard/selection or spoken text via HUD (no console flash).
local phrase = (jarvis.context.phrase or ""):lower()

local target = "auto"
if phrase:find("на русский", 1, true) or phrase:find("на русском", 1, true) then
  target = "ru"
elseif phrase:find("на английский", 1, true) or phrase:find("на английском", 1, true) then
  target = "en"
elseif phrase:find("to russian", 1, true) then
  target = "ru"
elseif phrase:find("to english", 1, true) then
  target = "en"
end

local strip = {
  "на русский язык", "на русском языке", "на русский", "на русском",
  "на английский язык", "на английском языке", "на английский", "на английском",
  "to russian", "to english",
}
for _, s in ipairs(strip) do
  phrase = phrase:gsub(s, " ")
end
phrase = phrase:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")

local prefixes = {
  "переведи это",
  "переведи выделенное",
  "переведи слово",
  "переведи текст",
  "переведи",
  "переводчик",
  "перевод",
  "translate this",
  "translate selection",
  "translate",
}

local text = phrase
for _, prefix in ipairs(prefixes) do
  if text:sub(1, #prefix) == prefix then
    text = text:sub(#prefix + 1):gsub("^%s+", "")
    break
  end
end
text = text:gsub("^[%s,.:;-]+", ""):gsub("%s+$", "")

-- Do NOT pass -Ui: launcher captures selection from the last real window first.
local args = {
  "-NoProfile",
  "-WindowStyle",
  "Hidden",
  "-STA",
  "-ExecutionPolicy",
  "Bypass",
  "-File",
  "resources/scripts/translate-hud.ps1",
  "-TargetLang",
  target,
}
if text ~= "" then
  local tmp = (jarvis.system.env("TEMP") or ".") .. "\\jarvis-translate-src-" .. tostring(os.time()) .. "-" .. tostring(math.random(100000, 999999)) .. ".txt"
  pcall(function()
    jarvis.fs.write(tmp, text)
  end)
  table.insert(args, "-TextFile")
  table.insert(args, tmp)
end

jarvis.system.exec("powershell", args)

return { chain = false }
