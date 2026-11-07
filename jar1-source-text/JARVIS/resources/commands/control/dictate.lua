-- Continuous dictation: «запиши» starts session; speech is typed until Esc / «останови».
-- Never paste the trigger word itself (that was the bug).
local phrase_raw = jarvis.context.phrase or ""
local phrase = phrase_raw:lower()

local wake = {
  "джарвис", "джервис", "гарвис", "джарви", "гарви", "джавис",
  "jarvis", "jervis", "hey jarvis", "джерри",
  "луна", "луну", "лунар", "luna", "lunar", "hey luna",
}
for _, w in ipairs(wake) do
  if phrase:sub(1, #w) == w then
    phrase = phrase:sub(#w + 1):gsub("^[%s,.:;-]+", "")
    break
  end
end
phrase = phrase:gsub("^[%s,.:;-]+", ""):gsub("[%s,.:;-]+$", "")

local prefixes = {
  "начинаю записывать",
  "начать запись",
  "начни запись",
  "режим диктовки",
  "режим печати",
  "начинаю печатать",
  "начинаю печать",
  "введи текст",
  "напечатать",
  "напечатай",
  "записывать",
  "записывай",
  "запись",
  "запиши",
  "печатать",
  "печатай",
  "диктовать",
  "диктуй",
  "напиши",
  "набери",
}

local start_only = {
  ["запиши"] = true,
  ["записывай"] = true,
  ["записывать"] = true,
  ["запись"] = true,
  ["диктуй"] = true,
  ["диктовать"] = true,
  ["напечатай"] = true,
  ["напечатать"] = true,
  ["печатай"] = true,
  ["печатать"] = true,
  ["напиши"] = true,
  ["набери"] = true,
  ["режим диктовки"] = true,
  ["режим печати"] = true,
  ["начинаю печатать"] = true,
  ["начинаю печать"] = true,
  ["начинаю записывать"] = true,
  ["начни запись"] = true,
  ["начать запись"] = true,
  ["введи текст"] = true,
}

local function start_continuous()
  -- MUST wait so dictate.active exists before next STT chunk
  jarvis.system.exec_wait("powershell", {
    "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
    "resources/scripts/dictate-control.ps1", "start",
  })
  jarvis.system.notify("Диктовка", "Перед каждым фрагментом скажи имя ассистента · Esc для выхода")
  return { chain = true }
end

-- Bare trigger → continuous (never paste the word «запиши»)
if start_only[phrase] then
  return start_continuous()
end

local text = phrase
local matched = ""
for _, prefix in ipairs(prefixes) do
  if text:sub(1, #prefix) == prefix then
    text = text:sub(#prefix + 1)
    matched = prefix
    break
  end
end
text = text:gsub("^[%s,.:;-]+", ""):gsub("[%s,.:;-]+$", "")

local fillers = {
  ["это"] = true, ["текст"] = true, ["сюда"] = true, ["мне"] = true,
  ["пожалуйста"] = true, ["сейчас"] = true,
}
if fillers[text] then text = "" end

-- Trigger + nothing useful → continuous
if matched ~= "" and text == "" then
  return start_continuous()
end

-- No prefix matched but this is the dictate command (fuzzy/intent) → continuous, do NOT paste
if matched == "" then
  return start_continuous()
end

-- «запиши привет мир» → paste only leftover once
if start_only[text] then
  return start_continuous()
end

jarvis.system.clipboard.set(text)
jarvis.sleep(60)
jarvis.system.exec("powershell", {
  "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
  "resources/scripts/input-control.ps1", "paste",
})
return { chain = false }
