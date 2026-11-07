# -*- coding: utf-8 -*-
"""Emit UTF-8 toast message for led-strip-control.ps1 (avoids PS1 encoding issues)."""
import sys
from pathlib import Path

MSGS = {
    "no_script": "Не найден скрипт led-strip-ble.py",
    "no_python": "Нужен Python 3.10+ на ПК (Bluetooth LED-лента)",
    "bleak_fail": "Не удалось установить библиотеку bleak",
    "no_device": "Лента не найдена. Включите контроллер и Bluetooth на ПК, скажите: найди ленту",
    "bleak_missing": "Нет библиотеки Bluetooth (bleak)",
    "unknown_color": "Неизвестный цвет",
    "fail": "Команда LED не выполнена",
    "on": "Лента включена",
    "off": "Лента выключена",
    "scan": "Лента привязана",
    "color": "Цвет: {0}",
    "brightness": "Яркость {0}%",
    "effect": "Эффект: {0}",
}

key = sys.argv[1] if len(sys.argv) > 1 else "fail"
arg = sys.argv[2] if len(sys.argv) > 2 else ""
tpl = MSGS.get(key, key)
try:
    text = tpl.format(arg) if "{0}" in tpl else tpl
except Exception:
    text = tpl
if len(sys.argv) > 3:
    Path(sys.argv[3]).write_text(text, encoding="utf-8")
else:
    sys.stdout.buffer.write((text + "\n").encode("utf-8", errors="replace"))
    sys.stdout.buffer.flush()
