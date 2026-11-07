-- Speak clipboard first, then selection. Silero via UTF-8 sidecar (no Lua byte-slicing).

local enabled = jarvis.settings.get("tts_enabled")
if enabled == "false" or enabled == "0" or enabled == "off" then
  jarvis.system.notify("Озвучка", "Озвучка выключена в настройках")
  return { chain = false }
end

local phrase_raw = jarvis.context.phrase or ""
local phrase = phrase_raw:lower()

local wake = {
  "джарвис", "джервис", "гарвис", "джарви", "гарви", "джавис",
  "jarvis", "jervis", "hey jarvis",
  "луна", "луну", "лунар", "luna", "lunar", "hey luna",
}
for _, w in ipairs(wake) do
  if phrase:sub(1, #w) == w then
    phrase = phrase:sub(#w + 1):gsub("^[%s,.:;-]+", "")
    break
  end
end

local prefixes = {
  "прочитай выделенное", "прочитай буфер", "прочитай текст", "прочитай вслух",
  "прочитай это", "прочитать эту", "прочитать это", "прочитать текст",
  "прочитать", "прочитай", "причитая это", "причитая", "прочтя это", "прочтя",
  "причта это", "причта",
  "озвучь выделенное", "озвучь буфер", "озвучь текст", "озвучь это", "озвучь",
  "озвучи это", "озвучи", "озвуч это", "озвуч текст", "озвуч",
  "прочти это", "прочти", "читай это", "читай",
}

local text = phrase
local matched_prefix = ""
for _, prefix in ipairs(prefixes) do
  if text:sub(1, #prefix) == prefix then
    text = text:sub(#prefix + 1)
    matched_prefix = prefix
    break
  end
end

text = text:gsub("^[%s,.:;-]+", ""):gsub("[%s,.:;-]+$", "")

local fillers = {
  ["это"] = true, ["эта"] = true, ["этот"] = true, ["эту"] = true,
  ["то"] = true, ["пожалуйста"] = true, ["сейчас"] = true,
  ["текст"] = true, ["выделенное"] = true, ["буфер"] = true,
  ["сюда"] = true, ["мне"] = true,
}

if fillers[text] then text = "" end
if text ~= "" then
  local only_filler = true
  for word in text:gmatch("%S+") do
    local w = word:gsub("^[%p]+", ""):gsub("[%p]+$", "")
    if not fillers[w] then only_filler = false; break end
  end
  if only_filler then text = "" end
end

-- Spoken leftovers after "прочитай …" are STT, not the copied document.
local trust_leftover = (matched_prefix ~= "" and text ~= "")
if not trust_leftover then text = "" end

local function capture_text()
  -- Copied text wins. Do not send Ctrl+C over an already-full clipboard.
  local ok_clip, clip_fn = pcall(function() return jarvis.system.clipboard.get end)
  if ok_clip and type(clip_fn) == "function" then
    local ok2, clip = pcall(function() return jarvis.system.clipboard.get() end)
    if ok2 and type(clip) == "string" then
      clip = clip:gsub("^%s+", ""):gsub("%s+$", "")
      if clip ~= "" then return clip end
    end
  end

  local ok_cap, cap_fn = pcall(function() return jarvis.capture_speak_text end)
  if ok_cap and type(cap_fn) == "function" then
    local ok3, cap = pcall(function() return jarvis.capture_speak_text() end)
    if ok3 and type(cap) == "string" then
      cap = cap:gsub("^%s+", ""):gsub("%s+$", "")
      if cap ~= "" then return cap end
    end
  end
  return ""
end

if text == "" then
  text = capture_text()
end

if text ~= "" then
  jarvis.speak(text)
  jarvis.system.notify("Озвучка", "Читаю… Первая загрузка Silero может занять до минуты.")
else
  jarvis.system.notify("Озвучка", "Сначала скопируй текст (Ctrl+C), потом скажи «озвучь».")
end

return { chain = false }
