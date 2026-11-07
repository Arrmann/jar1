-- Set LED strip color from spoken phrase (universal Lotus Lantern / ELK-BLEDOM).
local phrase = (jarvis.context.phrase or ""):lower()

local colors = {
  {"красный", "red"}, {"красная", "red"}, {"красным", "red"}, {"red", "red"},
  {"зеленый", "green"}, {"зелёный", "green"}, {"зеленая", "green"}, {"зелёная", "green"}, {"green", "green"},
  {"синий", "blue"}, {"синяя", "blue"}, {"синим", "blue"}, {"blue", "blue"},
  {"белый", "white"}, {"белая", "white"}, {"белым", "white"}, {"white", "white"},
  {"желтый", "yellow"}, {"жёлтый", "yellow"}, {"yellow", "yellow"},
  {"оранжевый", "orange"}, {"orange", "orange"},
  {"фиолетовый", "purple"}, {"purple", "purple"},
  {"розовый", "pink"}, {"pink", "pink"},
  {"голубой", "cyan"}, {"cyan", "cyan"},
  {"бирюзовый", "turquoise"},
  {"малиновый", "magenta"}, {"magenta", "magenta"},
  {"салатовый", "lime"}, {"lime", "lime"},
  {"золотой", "gold"}, {"gold", "gold"},
  {"теплый", "warm"}, {"тёплый", "warm"}, {"warm", "warm"},
  {"холодный", "cold"}, {"cold", "cold"},
  {"небо", "sky"}, {"ледяной", "ice"}, {"лёд", "ice"},
  {"сиреневый", "violet"}, {"коралловый", "coral"},
  {"мятный", "mint"}, {"янтарный", "amber"},
}

local pick = nil
for _, pair in ipairs(colors) do
  if phrase:find(pair[1], 1, true) then
    pick = pair[2]
    break
  end
end

if not pick then
  jarvis.system.notify("LED", "Скажите цвет: красный, синий, зелёный…")
  return { chain = true }
end

jarvis.system.run_python("resources/scripts/led-strip-ble.py", { "color", pick })
return { chain = false }
