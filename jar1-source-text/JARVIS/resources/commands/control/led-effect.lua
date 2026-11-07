-- LED effect from phrase (full Lotus / remote pattern set).
local phrase = (jarvis.context.phrase or ""):lower()

local effects = {
  -- classic remote 4 buttons
  {"флеш", "flash"}, {"flash", "flash"}, {"мигание", "flash"}, {"мигать", "flash"},
  {"строб", "strobe"}, {"strobe", "strobe"}, {"вспышк", "strobe"},
  {"фейд", "fade"}, {"fade", "fade"}, {"затухание", "fade"}, {"плавн", "fade"},
  {"smooth", "smooth"}, {"перелив", "crossfade"},
  -- jump / rainbow
  {"радуга", "rainbow"}, {"rainbow", "rainbow"},
  {"прыжк", "jump"}, {"jump", "jump"},
  {"три прыж", "jump3"}, {"семь прыж", "jump7"},
  -- breathe / gradual
  {"дыхание", "breathe"}, {"breathe", "breathe"},
  {"постепенн", "breathe"},
  -- color strobes
  {"строб красн", "strobe_red"}, {"красн строб", "strobe_red"},
  {"строб зелен", "strobe_green"}, {"зелен строб", "strobe_green"}, {"зелён строб", "strobe_green"},
  {"строб син", "strobe_blue"}, {"син строб", "strobe_blue"},
  {"строб желт", "strobe_yellow"}, {"строб жёлт", "strobe_yellow"},
  {"строб голу", "strobe_cyan"}, {"строб бел", "strobe_white"},
  {"строб фиолет", "strobe_purple"},
  -- gradual colors
  {"дыхание красн", "gradual_red"}, {"красн дыхание", "gradual_red"},
  {"дыхание зелен", "gradual_green"}, {"дыхание зелён", "gradual_green"},
  {"дыхание син", "gradual_blue"},
  {"дыхание бел", "gradual_white"},
}

local pick = "rainbow"
for _, pair in ipairs(effects) do
  if phrase:find(pair[1], 1, true) then
    pick = pair[2]
    break
  end
end

-- numeric "режим ленты 21"
local num = phrase:match("режим%s+ленты%s+(%d+)") or phrase:match("эффект%s+(%d+)") or phrase:match("паттерн%s+(%d+)")
if num then pick = num end

jarvis.system.run_python("resources/scripts/led-strip-ble.py", { "effect", pick })
return { chain = false }
