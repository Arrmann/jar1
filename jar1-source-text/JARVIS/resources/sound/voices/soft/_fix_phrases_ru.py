# -*- coding: utf-8 -*-
"""Rewrite popular/command.toml phrases.ru: Vosk-friendly RU, fewer bare singles."""
from __future__ import annotations

import re
from pathlib import Path

TOML = Path(r"C:\jarvisTOP\resources\commands\popular\command.toml")

# Full replacement for phrases.ru by command id
REPLACEMENTS: dict[str, list[str]] = {
    "browser_back": ["страница назад", "вернись назад", "браузер назад"],
    "browser_forward": ["страница вперёд", "страница вперед", "браузер вперёд"],
    "browser_incognito": ["открой инкогнито", "приватное окно", "открой приватное окно"],
    "browser_zoom_in_cmd": ["увеличь масштаб", "масштаб больше", "приблизь страницу"],
    "browser_zoom_out_cmd": ["уменьши масштаб", "масштаб меньше", "отдались от страницы"],
    "open_magnifier": ["открой лупу", "увеличительное стекло", "открой увеличительное стекло"],
    "open_focus_assist": ["режим фокусировки", "не беспокоить", "открой фокус"],
    "open_emoji_panel": ["открой эмодзи", "панель эмодзи", "эмодзи панель", "вин точка"],
    "open_calendar": ["открой календарь", "календарь виндовс", "гугл календарь"],
    "open_photos": ["открой фото", "открой фотографии", "открой галерею", "галерея виндовс"],
    "open_startup_apps": [
        "программы при запуске",
        "автозагрузка программ",
        "что запускается с виндовс",
        "автозагрузка виндовс",
    ],
    "open_storage": ["открой хранилище", "хранилище виндовс", "открой память"],
    "open_update": [
        "открой обновления",
        "обновления виндовс",
        "проверь обновления",
        "центр обновления",
    ],
    "reload_explorer": [
        "перезапусти проводник",
        "перезапуск проводника",
        "перезапусти эксплорер",
    ],
    "open_chatgpt": [
        "открой чат джипити",
        "открой чатгпт",
        "открой чат гпт",
        "чат джипити",
        "чатгпт",
    ],
    "open_deepseek": [
        "открой дипсик",
        "открой дип сик",
        "дипсик",
        "дип сик",
    ],
    "open_claude": [
        "открой клод",
        "открой клауд",
        "открой клод ии",
    ],
    "open_gemini": [
        "открой джемини",
        "открой гемини",
        "джемини",
        "гугл джемини",
    ],
    "open_twitch": ["открой твич", "твич"],
    "open_tiktok": ["открой тикток", "тикток"],
    "open_instagram": ["открой инстаграм", "открой инсту", "инстаграм"],
    "open_kinopoisk": ["открой кинопоиск", "кинопоиск", "кино поиск"],
    "open_ivi": ["открой иви", "открой и ви"],
    "open_wildberries": [
        "открой вайлдберриз",
        "открой вайлдбериз",
        "вайлдберриз",
        "вайлдбериз",
        "открой вб",
    ],
    "open_ozon": ["открой озон", "открой озон магазин"],
    "open_avito": ["открой авито", "авито"],
    "open_yandex": ["открой яндекс", "открой я ру", "яндекс"],
    "open_google_drive": [
        "открой гугл диск",
        "гугл диск",
        "открой гугл драйв",
        "гугл драйв",
    ],
    "open_news": ["открой новости", "гугл новости", "открой гугл новости"],
    "open_steam": ["открой стим", "стим"],
    "open_youtube_music": [
        "открой ютуб музыку",
        "ютуб музыка",
        "открой ютуб мьюзик",
    ],
    "open_zoom": ["открой зум", "открой зум конференцию"],
    "open_teams": [
        "открой тимс",
        "открой майкрософт тимс",
        "тимс",
    ],
    "open_meet": ["открой мит", "открой гугл мит", "гугл мит"],
    "open_word": ["открой ворд", "открой майкрософт ворд", "ворд"],
    "open_excel": ["открой эксель", "открой майкрософт эксель", "эксель"],
    "open_powerpoint": [
        "открой поверпоинт",
        "открой презентацию",
        "поверпоинт",
        "презентация",
    ],
    "open_notion": ["открой ноушен", "открой ноушн", "ноушен", "ноушн"],
    "open_github": [
        "открой гитхаб",
        "открой гит хаб",
        "гитхаб",
        "гит хаб",
        "запусти гитхаб",
    ],
    "open_rutube": [
        "открой рутуб",
        "рутуб",
        "открой рот",
        "рот убы",
        "открой рот убы",
        "ру туб",
    ],
    "open_pinterest": [
        "открой пинтерест",
        "пинтерест",
        "пинтерес",
        "пинты рост",
    ],
    "open_obs": ["открой обс", "открой обс студио"],
    "open_weather": ["открой погоду", "покажи погоду", "прогноз погоды"],
    "open_snip": ["открой ножницы", "фрагмент экрана", "снимок области"],
    "open_clock": ["открой часы", "открой будильники"],
    "input_print": ["отправь на печать", "распечатай", "распечатать документ"],
    "open_netflix": ["открой нетфликс", "нетфликс"],
}


def format_phrases(phrases: list[str]) -> str:
    # de-dupe preserve order
    seen = set()
    clean = []
    for p in phrases:
        p = p.strip()
        if not p or p in seen:
            continue
        seen.add(p)
        clean.append(p)
    if len(clean) == 1:
        return f'phrases.ru = ["{clean[0]}"]'
    lines = ["phrases.ru = ["]
    for p in clean:
        lines.append(f'    "{p}",')
    lines.append("]")
    return "\n".join(lines)


def main() -> None:
    text = TOML.read_text(encoding="utf-8")
    blocks = re.split(r"(\n\[\[commands\]\]\n)", text)
    # blocks[0] = header, then (sep, body)*
    out = [blocks[0]]
    changed = []
    i = 1
    while i < len(blocks):
        sep = blocks[i]
        body = blocks[i + 1] if i + 1 < len(blocks) else ""
        mid = re.search(r'id\s*=\s*"([^"]+)"', body)
        cid = mid.group(1) if mid else ""
        if cid in REPLACEMENTS:
            new_ph = format_phrases(REPLACEMENTS[cid])
            body2, n = re.subn(
                r"phrases\.ru\s*=\s*\[.*?\]",
                new_ph,
                body,
                count=1,
                flags=re.S,
            )
            if n:
                body = body2
                changed.append(cid)
            else:
                print("WARN no phrases.ru for", cid)
        out.append(sep)
        out.append(body)
        i += 2
    TOML.write_text("".join(out), encoding="utf-8")
    print("updated", len(changed), "commands")
    for c in changed:
        print(" ", c)


if __name__ == "__main__":
    main()
