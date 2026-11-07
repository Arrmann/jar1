-- Voice → photo: «джарвис создай фото …описание…»
-- Queues OpenRouter image generation into Neurochat history.

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
  "сгенерируй картинку",
  "сгенерируй изображение",
  "сгенерируй фото",
  "создай картинку",
  "создай изображение",
  "создай фото",
  "сделай картинку",
  "сделай изображение",
  "сделай фото",
  "створи картинку",
  "створи зображення",
  "створи фото",
  "зроби картинку",
  "зроби зображення",
  "зроби фото",
  "нарисуй картинку",
  "нарисуй изображение",
  "нарисуй фото",
  "нарисуй",
  "generate an image",
  "generate image",
  "create an image",
  "create image",
  "create a photo",
  "create photo",
  "draw an image",
  "draw image",
}

table.sort(prefixes, function(a, b) return #a > #b end)

local prompt = phrase
for _, prefix in ipairs(prefixes) do
  if prompt:sub(1, #prefix) == prefix then
    prompt = prompt:sub(#prefix + 1):gsub("^[%s,.:;-]+", "")
    break
  end
end
prompt = prompt:gsub("^[%s,.:;-]+", ""):gsub("[%s,.:;-]+$", "")

if prompt ~= "" and #phrase_raw >= #prompt then
  local orig = phrase_raw
  local low = orig:lower()
  local idx = low:find(prompt, 1, true)
  if idx then
    prompt = orig:sub(idx, idx + #prompt - 1)
  end
end

if prompt == "" then
  jarvis.system.notify("Фото", "Скажи: джарвис создай фото …описание")
  return { chain = true }
end

local ok, sent = pcall(function()
  return jarvis.neurochat.image(prompt)
end)

if not ok or not sent then
  jarvis.system.notify("Фото", "Не удалось запустить генерацию. Запусти JARVIS через START_JARVIS.bat")
  return { chain = false }
end

jarvis.system.notify("Фото", prompt)
return { chain = false }
