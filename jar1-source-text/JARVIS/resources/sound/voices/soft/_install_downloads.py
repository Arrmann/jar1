# -*- coding: utf-8 -*-
from __future__ import annotations

import shutil
from pathlib import Path

SRC = Path(r"C:\Users\Мирослав\Downloads")
DST = Path(__file__).resolve().parent / "ru"
DST.mkdir(parents=True, exist_ok=True)

# Unique markers (prefer emotion+phrase combo to avoid collisions)
RULES: list[tuple[str, list[str]]] = [
    ("Слушаю-тебя! (1)", ["reply1"]),
    ("(smiling,-friendly)-Да,-я-тут!", ["reply2"]),
    ("(friendly,-warm)-Я-здесь!", ["reply3"]),
    ("(smiling,-eager,-friendly)-Готова-помочь!", ["reply5"]),
    ("(smiling,-friendly,-satisfied)-Готово!", ["ok1"]),
    ("(smiling,-friendly)-Сделано!", ["ok2"]),
    ("(warm,-friendly)-Хорошо!", ["ok3"]),
    ("(smiling,-friendly)-Конечно!", ["ok4"]),
    ("(smiling,-warm)-Пожалуйста!", ["thanks1"]),
    ("(friendly,-warm)-Не-за-что!", ["thanks2"]),
    ("(smiling,-friendly)-Рада-помочь!", ["thanks3"]),
    ("(smiling,-warm)-Пока!", ["goodbye1"]),
    ("(friendly,-warm)-До-связи!", ["goodbye2"]),
    ("(smiling,-friendly,-warm)-Хорошего-дня!", ["goodbye3"]),
    ("(friendly,-clear)-Время-вышло!", ["timer_done", "timer_done1"]),
    ("(friendly,-soft-alert)-Таймер-сработал!", ["timer_done2"]),
    ("(smiling,-friendly)-Привет,-рада-слышать!", ["hello2"]),
    ("(smiling,-friendly,-warm)-Привет!", ["hello1", "hello3", "greet1"]),
    ("Всё-хорошо,-а-у-тебя-к", ["howare1"]),
    ("(cheerful,-friendly)-Отлично,-слушаю-тебя!", ["howare2"]),
    ("(smiling,-eager,-friendly)-Хорошо!-Чем-помочь", ["howare3"]),
    ("(smiling,-soft,-warm)-Доброе-утро!", ["greet_morning"]),
    ("(friendly,-warm)-Добрый-день!", ["greet_day"]),
    ("(warm,-friendly)-Добрый-вечер!", ["greet_evening"]),
    ("(soft,-warm,-gentle)-Доброй-ночи!", ["greet_night"]),
]

FALLBACK = {
    "reply4": "reply2",
    "ok5": "ok4",
    "timer_done3": "timer_done1",
}

EXPECTED = [
    "reply1", "reply2", "reply3", "reply4", "reply5",
    "ok1", "ok2", "ok3", "ok4", "ok5",
    "thanks1", "thanks2", "thanks3",
    "goodbye1", "goodbye2", "goodbye3",
    "timer_done", "timer_done1", "timer_done2", "timer_done3",
    "hello1", "hello2", "hello3",
    "howare1", "howare2", "howare3",
    "greet1", "greet_morning", "greet_day", "greet_evening", "greet_night",
]


def find_file(files: list[Path], needle: str) -> Path | None:
    for f in files:
        if needle in f.name:
            return f
    return None


def main() -> None:
    files = sorted(SRC.glob("Спокойный-2026-10-17*.mp3"))
    print(f"found {len(files)} downloads")

    for needle, stems in RULES:
        hit = find_file(files, needle)
        if not hit and "Слушаю-тебя!" in needle:
            hit = find_file(files, "Слушаю-тебя!.mp3")
        if not hit:
            print(f"MISSING source: {needle}")
            continue
        for stem in stems:
            out = DST / f"{stem}.mp3"
            shutil.copy2(hit, out)
            print(f"OK {stem}")

    for dest, src in FALLBACK.items():
        d, s = DST / f"{dest}.mp3", DST / f"{src}.mp3"
        if not d.exists() and s.exists():
            shutil.copy2(s, d)
            print(f"FALLBACK {dest} <- {src}")

    missing = [e for e in EXPECTED if not (DST / f"{e}.mp3").exists()]
    present = list(DST.glob("*.mp3"))
    react = [p for p in present if not p.name.startswith("cmd_")]
    print(f"reaction mp3: {len(react)}")
    if missing:
        print("STILL MISSING:", ", ".join(missing))
    else:
        print("All reaction slots filled")


if __name__ == "__main__":
    main()
