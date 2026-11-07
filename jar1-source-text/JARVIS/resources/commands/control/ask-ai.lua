-- Voice → Neurochat: «джарвис скажи …вопрос…»
-- Opens the GUI Neurochat tab and sends the question there (LLM + TTS in UI).

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
  "скажи мне",
  "скажи",
  "ответь на вопрос",
  "ответь мне",
  "ответь",
  "спроси у нейросети",
  "спроси нейросеть",
  "спроси нейронку",
  "спроси у ии",
  "спроси у ai",
  "спроси ии",
  "спроси gpt",
  "спроси chatgpt",
  "спроси",
  "tell me",
  "say",
  "answer me",
  "answer",
  "ask the ai",
  "ask ai",
  "ask gpt",
  "ask",
}

table.sort(prefixes, function(a, b) return #a > #b end)

local question = phrase
local used_prefix = nil
for _, prefix in ipairs(prefixes) do
  if question:sub(1, #prefix) == prefix then
    question = question:sub(#prefix + 1):gsub("^[%s,.:;-]+", "")
    used_prefix = prefix
    break
  end
end
question = question:gsub("^[%s,.:;-]+", ""):gsub("[%s,.:;-]+$", "")

-- Keep «скажи дату» for local commands.
local reserved = {
  "дату", "дата", "дату сегодня", "какое число", "какой день", "день недели",
  "date", "the date", "what date",
}
if used_prefix == "скажи" or used_prefix == "скажи мне" or used_prefix == "say" or used_prefix == "tell me" then
  local qlow = question:lower()
  for _, r in ipairs(reserved) do
    if qlow == r or qlow:sub(1, #r + 1) == (r .. " ") then
      return { chain = true }
    end
  end
end

if question ~= "" and #phrase_raw >= #question then
  local orig = phrase_raw
  local low = orig:lower()
  local idx = low:find(question, 1, true)
  if idx then
    question = orig:sub(idx, idx + #question - 1)
  end
end

if question == "" then
  jarvis.system.notify("Нейрочат", "Скажи: джарвис скажи … твой вопрос")
  return { chain = true }
end

local ok, sent = pcall(function()
  return jarvis.neurochat.ask(question)
end)

if not ok or not sent then
  jarvis.system.notify("Нейрочат", "Не удалось открыть чат. Запусти JARVIS через START_JARVIS.bat")
  return { chain = false }
end

jarvis.system.notify("Нейрочат", question)
return { chain = false, silent = true }
