-- Voice → Neurochat with screen: «что на экране» / «посмотри на экран …»
-- Captures desktop and asks a vision model (DeepSeek flash / Gemini / …).

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

local defaults = {
  "что на экране",
  "что у меня на экране",
  "что там на экране",
  "что сейчас на экране",
  "опиши экран",
  "опиши что на экране",
  "посмотри на экран",
  "посмотри экран",
  "посмотри что на экране",
  "глянь на экран",
  "глянь экран",
  "what's on my screen",
  "whats on my screen",
  "what is on my screen",
  "look at the screen",
  "look at my screen",
  "describe the screen",
  "describe my screen",
}

local question = nil
for _, d in ipairs(defaults) do
  if phrase == d then
    question = "Что сейчас на экране? Кратко."
    break
  end
end

if not question then
  local prefixes = {
    "посмотри на экран и скажи",
    "посмотри на экран и",
    "посмотри на экран",
    "посмотри экран и",
    "посмотри экран",
    "вопрос по экрану",
    "скажи по экрану",
    "ответь по экрану",
    "по экрану",
    "на экране",
    "look at the screen and",
    "look at my screen and",
    "look at the screen",
    "look at my screen",
    "about the screen",
    "on the screen",
  }
  table.sort(prefixes, function(a, b) return #a > #b end)
  for _, prefix in ipairs(prefixes) do
    if phrase:sub(1, #prefix) == prefix then
      local rest = phrase:sub(#prefix + 1):gsub("^[%s,.:;-]+", ""):gsub("[%s,.:;-]+$", "")
      if rest == "" then
        question = "Что сейчас на экране? Кратко."
      else
        local orig = phrase_raw
        local low = orig:lower()
        local idx = low:find(rest, 1, true)
        if idx then
          question = orig:sub(idx, idx + #rest - 1)
        else
          question = rest
        end
      end
      break
    end
  end
end

if not question or question == "" then
  jarvis.system.notify("Экран", "Скажи: джарвис что на экране — или вопрос по экрану …")
  return { chain = true }
end

local ok, sent = pcall(function()
  return jarvis.neurochat.ask_screen(question)
end)

if not ok or not sent then
  jarvis.system.notify("Экран", "Не удалось открыть чат. Запусти JARVIS через START_JARVIS.bat")
  return { chain = false }
end

jarvis.system.notify("Экран", question)
return { chain = false, silent = true }
