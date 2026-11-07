# -*- coding: utf-8 -*-
"""Generate Soft voice pack phrase script — friendly + Fish Audio markup."""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
MITA_RU = ROOT / "resources" / "sound" / "voices" / "mita" / "ru"
CMDS = ROOT / "resources" / "commands"
OUT = Path(__file__).resolve().parent / "PHRASES.ru.md"

# Default Fish emotion for short confirms
FISH = "smiling, friendly, warm"

# cmd_* — как отвечает милая девушка после действия (не робот-диктор)
CONFIRM: dict[str, str] = {
    "cmd_brightness_down": "Сделала потемнее",
    "cmd_brightness_up": "Сделала поярче",
    "cmd_browser_back": "Вернула назад",
    "cmd_browser_close_tab": "Закрыла вкладку",
    "cmd_browser_downloads": "Открыла загрузки",
    "cmd_browser_incognito": "Открыла инкогнито",
    "cmd_browser_new_tab": "Открыла новую вкладку",
    "cmd_browser_next_tab": "Перешла на следующую",
    "cmd_browser_open": "Открыла браузер",
    "cmd_browser_prev_tab": "Вернула прошлую вкладку",
    "cmd_browser_refresh": "Обновила",
    "cmd_browser_reopen_tab": "Вернула вкладку",
    "cmd_cancel_shutdown": "Отменила выключение",
    "cmd_clipboard_history": "Открыла буфер",
    "cmd_close_active": "Закрыла",
    "cmd_dictate": "Диктуй, я слушаю",
    "cmd_empty_trash": "Очистила корзину",
    "cmd_game_mode": "Включила игровой режим",
    "cmd_gestures_off": "Выключила жесты",
    "cmd_gestures_on": "Включила жесты",
    "cmd_input_copy": "Скопировала",
    "cmd_input_cut": "Вырезала",
    "cmd_input_find": "Открыла поиск",
    "cmd_input_new_doc": "Сделала новый документ",
    "cmd_input_paste": "Вставила",
    "cmd_input_print": "Отправила на печать",
    "cmd_input_redo": "Вернула как было",
    "cmd_input_save": "Сохранила",
    "cmd_input_select_all": "Выделила всё",
    "cmd_input_switch_lang": "Переключила язык",
    "cmd_input_undo": "Отменила",
    "cmd_lock_pc": "Заблокировала",
    "cmd_maximize_window": "Развернула на весь экран",
    "cmd_media_next": "Включила следующий",
    "cmd_media_play_pause": "Поставила на паузу",
    "cmd_media_prev": "Вернула прошлый трек",
    "cmd_media_stop": "Остановила",
    "cmd_minimize_all": "Всё свернула",
    "cmd_minimize_window": "Свернула",
    "cmd_open_about_pc": "Открыла про компьютер",
    "cmd_open_avito": "Открыла Авито",
    "cmd_open_bluetooth": "Открыла блютуз",
    "cmd_open_calculator": "Открыла калькулятор",
    "cmd_open_calendar": "Открыла календарь",
    "cmd_open_camera": "Открыла камеру",
    "cmd_open_chatgpt": "Открыла Чатджипити",
    "cmd_open_claude": "Открыла Клода",
    "cmd_open_cursor": "Открыла Курсор",
    "cmd_open_deepseek": "Открыла Дипсик",
    "cmd_open_desktop_folder": "Открыла рабочий стол",
    "cmd_open_discord": "Открыла Дискорд",
    "cmd_open_display_settings": "Открыла настройки экрана",
    "cmd_open_documents": "Открыла документы",
    "cmd_open_downloads": "Открыла загрузки",
    "cmd_open_emoji_panel": "Открыла эмодзи",
    "cmd_open_excel": "Открыла Эксель",
    "cmd_open_explorer": "Открыла проводник",
    "cmd_open_gemini": "Открыла Джемини",
    "cmd_open_github": "Открыла Гитхаб",
    "cmd_open_gmail": "Открыла почту",
    "cmd_open_google_drive": "Открыла Гугл диск",
    "cmd_open_instagram": "Открыла Инстаграм",
    "cmd_open_ivi": "Открыла Иви",
    "cmd_open_kinopoisk": "Открыла Кинопоиск",
    "cmd_open_maps": "Открыла карты",
    "cmd_open_meet": "Открыла Мит",
    "cmd_open_netflix": "Открыла Нетфликс",
    "cmd_open_news": "Открыла новости",
    "cmd_open_night_light": "Включила ночной свет",
    "cmd_open_notepad": "Открыла блокнот",
    "cmd_open_notion": "Открыла Ноушен",
    "cmd_open_obs": "Открыла ОБС",
    "cmd_open_ozon": "Открыла Озон",
    "cmd_open_paint": "Открыла Пейнт",
    "cmd_open_photos": "Открыла фото",
    "cmd_open_pinterest": "Открыла Пинтерест",
    "cmd_open_powerpoint": "Открыла презентацию",
    "cmd_open_recycle_bin": "Открыла корзину",
    "cmd_open_rutube": "Открыла Рутуб",
    "cmd_open_screenshots_folder": "Открыла скриншоты",
    "cmd_open_settings": "Открыла параметры",
    "cmd_open_snip": "Открыла ножницы",
    "cmd_open_sound_settings": "Открыла звук",
    "cmd_open_startup_apps": "Открыла автозагрузку",
    "cmd_open_steam": "Открыла Стим",
    "cmd_open_storage": "Открыла память",
    "cmd_open_task_manager": "Открыла диспетчер",
    "cmd_open_teams": "Открыла Тимс",
    "cmd_open_telegram": "Открыла Телеграм",
    "cmd_open_terminal": "Открыла терминал",
    "cmd_open_tiktok": "Открыла Тикток",
    "cmd_open_translate": "Открыла переводчик",
    "cmd_open_twitch": "Открыла Твич",
    "cmd_open_update": "Открыла обновления",
    "cmd_open_vk": "Открыла Вконтакте",
    "cmd_open_weather": "Открыла погоду",
    "cmd_open_whatsapp": "Открыла Ватсап",
    "cmd_open_wifi": "Открыла вайфай",
    "cmd_open_wildberries": "Открыла Вайлдберриз",
    "cmd_open_word": "Открыла Ворд",
    "cmd_open_yandex_disk": "Открыла Яндекс диск",
    "cmd_open_yandex_maps": "Открыла Яндекс карты",
    "cmd_open_yandex_music": "Открыла Яндекс музыку",
    "cmd_open_yandex": "Открыла Яндекс",
    "cmd_open_youtube_music": "Открыла Ютуб музыку",
    "cmd_open_youtube": "Открыла Ютуб",
    "cmd_open_zoom": "Открыла Зум",
    "cmd_reload_explorer": "Перезапустила проводник",
    "cmd_remind_cancel": "Убрала напоминание",
    "cmd_remind": "Хорошо, напомню",
    "cmd_restart_pc": "Перезагружаю",
    "cmd_screenshot": "Сделала скриншот",
    "cmd_search_google": "Ищу в Гугле",
    "cmd_search_wiki": "Открыла Википедию",
    "cmd_search_yandex": "Ищу в Яндексе",
    "cmd_search_youtube": "Ищу на Ютубе",
    "cmd_show_desktop": "Показала рабочий стол",
    "cmd_shutdown_pc": "Выключаю",
    "cmd_sleep_pc": "Усыпляю компьютер",
    "cmd_speak": "Читаю",
    "cmd_speak_stop": "Хорошо, остановила",
    "cmd_switch_window": "Переключила окно",
    "cmd_timer_set": "Поставила таймер",
    "cmd_translate": "Открыла переводчик",
    "cmd_use_browser_chrome": "Поставила Хром",
    "cmd_use_browser_yandex": "Поставила Яндекс браузер",
    "cmd_volume_down": "Сделала потише",
    "cmd_volume_mute": "Выключила звук",
    "cmd_volume_unmute": "Вернула звук",
    "cmd_volume_up": "Сделала погромче",
}

# reactions: (filename_stem, plain_text, fish_line)
# fish_line = full paste into Fish TTS box
REACTIONS: list[tuple[str, str, str]] = []


def fish(text: str, tags: str = FISH) -> str:
    t = text.strip()
    if not t.endswith(("!", "?", "…")):
        t = t + "!"
    return f"({tags}) {t}"


def build_reactions() -> list[tuple[str, str, str]]:
    rows: list[tuple[str, str, str]] = []

    reply = [
        ("reply1", "Слушаю тебя", "smiling, friendly, warm"),
        ("reply2", "Да, я тут", "smiling, friendly"),
        ("reply3", "Я здесь", "friendly, warm"),
        ("reply4", "Да-да?", "curious, friendly, smiling"),
        ("reply5", "Готова помочь", "smiling, eager, friendly"),
    ]
    ok = [
        ("ok1", "Готово", "smiling, friendly, satisfied"),
        ("ok2", "Сделано", "smiling, friendly"),
        ("ok3", "Хорошо", "warm, friendly"),
        ("ok4", "Конечно", "smiling, friendly"),
        ("ok5", "Есть", "cheerful, friendly"),
    ]
    thanks = [
        ("thanks1", "Пожалуйста", "smiling, warm"),
        ("thanks2", "Не за что", "friendly, warm"),
        ("thanks3", "Рада помочь", "smiling, friendly"),
    ]
    goodbye = [
        ("goodbye1", "Пока", "smiling, warm"),
        ("goodbye2", "До связи", "friendly, warm"),
        ("goodbye3", "Хорошего дня", "smiling, friendly, warm"),
    ]
    timer = [
        ("timer_done", "Время вышло", "friendly, clear"),
        ("timer_done1", "Время вышло", "friendly, clear"),
        ("timer_done2", "Таймер сработал", "friendly, soft alert"),
        ("timer_done3", "Напоминаю тебе", "warm, friendly"),
    ]
    hello = [
        ("hello1", "Привет", "smiling, friendly, warm"),
        ("hello2", "Привет, рада слышать", "smiling, friendly"),
        ("hello3", "Привет", "cheerful, friendly"),
    ]
    howare = [
        ("howare1", "Всё хорошо, а у тебя как?", "smiling, friendly, warm"),
        ("howare2", "Отлично, слушаю тебя", "cheerful, friendly"),
        ("howare3", "Хорошо! Чем помочь?", "smiling, eager, friendly"),
    ]
    greet = [
        ("greet1", "Привет", "smiling, friendly, warm"),
        ("greet_morning", "Доброе утро", "smiling, soft, warm"),
        ("greet_day", "Добрый день", "friendly, warm"),
        ("greet_evening", "Добрый вечер", "warm, friendly"),
        ("greet_night", "Доброй ночи", "soft, warm, gentle"),
    ]

    for stem, text, tags in reply + ok + thanks + goodbye + timer + hello + howare + greet:
        rows.append((stem, text, fish(text, tags)))
    return rows


def load_sound_map() -> dict[str, str]:
    out: dict[str, str] = {}
    for toml in CMDS.rglob("command.toml"):
        text = toml.read_text(encoding="utf-8", errors="replace")
        for block in re.split(r"\n\[\[", text):
            if not re.search(r'id\s*=\s*"([^"]+)"', block):
                continue
            sounds = []
            for m in re.finditer(r"sounds\.ru\s*=\s*\[(.*?)\]", block, re.S):
                sounds += re.findall(r'"([^"]+)"', m.group(1))
            phrases = []
            for m in re.finditer(r"phrases\.ru\s*=\s*\[(.*?)\]", block, re.S):
                phrases += re.findall(r'"([^"]+)"', m.group(1))
            phr = phrases[0] if phrases else ""
            for s in sounds:
                if s not in out and phr:
                    out[s] = phr
    return out


def row(stem: str, plain: str, fish_line: str, hint: str = "") -> str:
    hint_col = f" | {hint}" if hint else ""
    return f"| `{stem}.mp3` | {plain} | `{fish_line}`{hint_col} |"


def main() -> None:
    files = sorted(p.stem for p in MITA_RU.glob("*.mp3"))
    cmds = [f for f in files if f.startswith("cmd_")]
    sound_hint = load_sound_map()
    reactions = build_reactions()

    lines: list[str] = []
    lines += [
        "# Soft — дружелюбный скрипт + разметка Fish Audio",
        "",
        "Голос: милый, тёплый, **живой человек**. Без нудятины и без «подруги/романтики».",
        "Продукт — **JARVIS**. Файлы → `soft/ru/` с точными именами.",
        "",
        "## Как генерить в Fish (обязательно)",
        "",
        "1. Модель: **Fish Audio Drama 3** (или новее).",
        "2. Скорость: **1.05–1.1×** (не 1.0 — иначе плоская).",
        "3. В поле текста вставляй **целиком колонку «Fish»** — со скобками.",
        "4. Делай 2–3 дубля, бери самый тёплый.",
        "5. Не озвучивай одно слово без эмо-тега — будет «нудная бабенция».",
        "",
        "Примеры тегов: `(smiling, friendly, warm)`, `(cheerful, friendly)`, `(curious, friendly)`.",
        "",
        "---",
        "",
        "## A. Реакции (вариативность)",
        "",
        "| файл | что слышно | **вставь в Fish как есть** |",
        "|------|------------|---------------------------|",
    ]
    for stem, plain, fl in reactions:
        lines.append(row(stem, plain, fl))

    lines += [
        "",
        "### Блоки для копипаста в Fish (реакции)",
        "",
        "```",
    ]
    for _stem, _plain, fl in reactions:
        lines.append(fl)
    lines += [
        "```",
        "",
        "---",
        "",
        f"## B. Команды `cmd_*` — **{len(cmds)}** файлов (как у Миты)",
        "",
        "Короткие тёплые подтверждения. В Fish — всегда с тегом.",
        "",
        "| файл | что слышно | **Fish** | фраза вызова (подсказка) |",
        "|------|------------|----------|--------------------------|",
    ]

    missing = []
    for stem in cmds:
        plain = CONFIRM.get(stem)
        if not plain:
            plain = stem.replace("cmd_", "").replace("_", " ")
            missing.append(stem)
        fl = fish(plain)
        hint = sound_hint.get(stem, "")
        lines.append(f"| `{stem}.mp3` | {plain} | `{fl}` | {hint} |")

    lines += [
        "",
        "### Блоки для копипаста в Fish (cmd)",
        "",
        "```",
    ]
    for stem in cmds:
        plain = CONFIRM.get(stem) or stem.replace("cmd_", "").replace("_", " ")
        lines.append(fish(plain))
    lines += [
        "```",
        "",
        "---",
        "",
        "## C. Итого",
        "",
        f"- реакции: **{len(reactions)}**",
        f"- cmd_*: **{len(cmds)}**",
        f"- **всего {len(reactions) + len(cmds)}** mp3",
        "",
        "## D. Не озвучивать",
        "- `not_found` / `error` — тишина (как у Миты)",
        "",
    ]
    if missing:
        lines.append(f"> Без ручного CONFIRM: {', '.join(missing)}")
        lines.append("")

    OUT.write_text("\n".join(lines), encoding="utf-8")
    print(f"Wrote {OUT}")
    print(f"reactions={len(reactions)} cmds={len(cmds)} total={len(reactions)+len(cmds)}")
    if missing:
        print("FALLBACK", missing)


if __name__ == "__main__":
    main()
