-- Engine from spoken words first. Intent id alone must NOT pick Yandex/Wiki/YouTube
-- (classifier often confuses shared "найди …" training phrases).
local phrase = (jarvis.context.phrase or ""):lower()

local function has_any(text, words)
  for _, w in ipairs(words) do
    if text:find(w, 1, true) then
      return true
    end
  end
  return false
end

local engine = "google"
if has_any(phrase, {
  "в яндексе", "яндексе", "яндекс найди", "поиск яндекс", "яндекс поиск",
  "yandex search", "search yandex", "find on yandex"
}) then
  engine = "yandex"
elseif has_any(phrase, {
  "на ютубе", "на ютюбе", "ютубе", "ютюбе", "ютуб", "ютюб", "youtube", "на youtube", "ютube"
}) then
  engine = "youtube"
elseif has_any(phrase, {
  "в википедии", "википедии", "википедия", "википедию", "wikipedia"
}) then
  engine = "wiki"
end

-- Strip every known prefix, longest first (even if wrong intent won).
local all_prefixes = {
  "найди в википедии", "ищи в википедии", "найди википедия", "открой википедию",
  "найди в яндексе", "поиск в яндексе", "яндекс найди", "поиск яндекс",
  "найди на ютубе", "поиск на ютубе", "на ютубе",
  "search yandex", "yandex search", "find on yandex",
  "youtube search", "search youtube", "find on youtube",
  "wiki search", "wikipedia",
  "загугли", "найди", "поиск", "search", "google", "find",
  "википедия", "ютуб", "youtube",
}

table.sort(all_prefixes, function(a, b) return #a > #b end)

local text = phrase
for _, prefix in ipairs(all_prefixes) do
  if text:sub(1, #prefix) == prefix then
    text = text:sub(#prefix + 1):gsub("^%s+", ""):gsub("^[%s,.:;-]+", "")
    break
  end
end

text = text
  :gsub("^в%s+яндексе%s+", "")
  :gsub("^в%s+википедии%s+", "")
  :gsub("^на%s+ютубе%s+", "")
  :gsub("^в%s+", "")
  :gsub("^на%s+", "")
  :gsub("^яндексе%s+", "")
  :gsub("^википедии%s+", "")
  :gsub("^ютубе%s+", "")
  :gsub("^%s+", "")
  :gsub("%s+$", "")

if text == "" then
  if engine == "wiki" then
    jarvis.system.exec("powershell", {
      "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
      "resources/scripts/open-url.ps1", "https://ru.wikipedia.org",
    })
    return { chain = false }
  end
  jarvis.system.notify("Поиск", "Скажите: найди … ваш запрос")
  return { chain = true }
end

jarvis.system.exec("powershell", {
  "-NoProfile",
  "-ExecutionPolicy",
  "Bypass",
  "-File",
  "resources/scripts/open-target.ps1",
  "search",
  engine .. ":" .. text
})

return { chain = false }
