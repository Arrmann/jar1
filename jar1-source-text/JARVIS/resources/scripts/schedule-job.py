#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""JARVIS schedule helper: timers, reminders, PC shutdown. UTF-8 safe on all Windows PCs."""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
import uuid
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any, Optional, Tuple


def data_dir() -> Path:
    override = (os.environ.get("JARVIS_CONFIG_DIR") or "").strip()
    if override:
        return Path(override)
    local = (os.environ.get("LOCALAPPDATA") or "").strip()
    if local:
        pointer = Path(local) / "JARVIS" / "active-config-dir.txt"
        try:
            lines = pointer.read_text(encoding="utf-8").splitlines()
        except OSError:
            lines = []
        line = lines[0].strip() if lines else ""
        if line:
            pointed = Path(line)
            if pointed.is_dir():
                return pointed
    appdata = Path(os.environ.get("APPDATA") or str(Path.home() / "AppData" / "Roaming"))
    return appdata / "com.jarvisn.assistant"


def reminders_path() -> Path:
    return data_dir() / "reminders.json"


WORDS = {
    "ноль": 0,
    "нуль": 0,
    "один": 1,
    "одна": 1,
    "одно": 1,
    "одну": 1,
    "два": 2,
    "две": 2,
    "пару": 2,
    "три": 3,
    "четыре": 4,
    "пять": 5,
    "шесть": 6,
    "семь": 7,
    "восемь": 8,
    "девять": 9,
    "десять": 10,
    "одиннадцать": 11,
    "двенадцать": 12,
    "тринадцать": 13,
    "четырнадцать": 14,
    "пятнадцать": 15,
    "шестнадцать": 16,
    "семнадцать": 17,
    "восемнадцать": 18,
    "девятнадцать": 19,
    "двадцать": 20,
    "тридцать": 30,
    "сорок": 40,
    "пятьдесят": 50,
    "шестьдесят": 60,
    "семьдесят": 70,
    "восемьдесят": 80,
    "девяносто": 90,
    "сто": 100,
    "двести": 200,
    "триста": 300,
}

# Compound word-number BEFORE a unit (never include unit words here — that caused 50s→1s bug).
WORD_NUM_RE = (
    r"(?:"
    r"(?:(?:двести|триста|сто)\s+)?"
    r"(?:"
    r"(?:двадцать|тридцать|сорок|пятьдесят|шестьдесят|семьдесят|восемьдесят|девяносто)"
    r"(?:\s+(?:один|одна|одно|одну|два|две|три|четыре|пять|шесть|семь|восемь|девять))?"
    r"|"
    r"одиннадцать|двенадцать|тринадцать|четырнадцать|пятнадцать|шестнадцать|"
    r"семнадцать|восемнадцать|девятнадцать|"
    r"десять|"
    r"ноль|нуль|один|одна|одно|одну|два|две|пару|три|четыре|пять|шесть|семь|восемь|девять"
    r")"
    r")"
)

UNIT_RE = (
    r"(секунд[уыа]?|сек|минут[уыа]?|мин|"
    r"час(?:а|ов)?|часа|ч|"
    r"дней|дня|день|сутки|суток|недел[юиь]?)"
)


def norm(s: str) -> str:
    return (
        (s or "")
        .lower()
        .replace("ё", "е")
        .replace("«", " ")
        .replace("»", " ")
        .replace('"', " ")
    )


def parse_word_number(chunk: str) -> Optional[int]:
    chunk = re.sub(r"\s+", " ", norm(chunk)).strip()
    if not chunk:
        return None
    if chunk.isdigit():
        return int(chunk)
    total = 0
    any_hit = False
    for part in chunk.split():
        if part not in WORDS:
            return None
        total += WORDS[part]
        any_hit = True
    return total if any_hit else None


def unit_to_seconds(n: int, unit: str) -> Tuple[int, str]:
    u = norm(unit)
    n = max(1, int(n))
    if u.startswith("сек"):
        return n, f"{n} секунд"
    if u.startswith("мин"):
        return n * 60, f"{n} минут"
    if u.startswith("ч"):
        return n * 3600, f"{n} часов"
    if u.startswith("недел"):
        return n * 7 * 86400, f"{n} недель"
    return n * 86400, f"{n} дней"


def parse_due(phrase: str, now: Optional[datetime] = None) -> Optional[Tuple[datetime, str, str, Optional[int]]]:
    """Return (due, label, message_text, offset_sec|None) or None."""
    now = now or datetime.now()
    p = re.sub(r"[,.;:!?]", " ", norm(phrase))
    p = re.sub(r"\s+", " ", p).strip()
    # Soft ASR cleanups that do not change meaning of clear phrases
    p = re.sub(r"\bпоставь\s+таймер\s+на\s+стой\b", "поставь таймер на", p)
    p = re.sub(r"\bтаймер\s+на\s+стой\b", "таймер на", p)
    due: Optional[datetime] = None
    label = ""
    offset_sec: Optional[int] = None

    if re.search(r"(?:^|\s)(?:через\s+|на\s+)?полчаса(?:\s|$)", p):
        offset_sec = 30 * 60
        label = "30 минут"
    elif re.search(r"(?:^|\s)(?:через\s+|на\s+)?полтора\s*час", p):
        offset_sec = 90 * 60
        label = "1.5 часа"

    # Digits + unit: "10 секунд", "2 часа", "50 часов"
    if offset_sec is None:
        m = re.search(rf"(?:через\s+|на\s+)?(\d+)\s*{UNIT_RE}", p)
        if m:
            offset_sec, label = unit_to_seconds(int(m.group(1)), m.group(2))

    # Word number + unit: "двадцать секунд", "пятьдесят часов", "двадцать пять минут"
    if offset_sec is None:
        m = re.search(rf"(?:через\s+|на\s+)?({WORD_NUM_RE})\s*{UNIT_RE}", p)
        if m:
            n = parse_word_number(m.group(1))
            if n is not None:
                offset_sec, label = unit_to_seconds(n, m.group(2))

    # Bare unit = 1: "на секунду", "на минуту", "на час", "через час"
    if offset_sec is None:
        m = re.search(
            r"(?:через\s+|на\s+)?(секунд[уыа]|сек|минут[уыа]|мин|час(?:ик)?|день|дня|неделю)(?:\s|$)",
            p,
        )
        if m:
            bare = m.group(1)
            if bare.startswith("сек"):
                offset_sec, label = 1, "1 секунда"
            elif bare.startswith("мин"):
                offset_sec, label = 60, "1 минута"
            elif bare.startswith("час"):
                offset_sec, label = 3600, "1 час"
            elif bare.startswith("недел"):
                offset_sec, label = 7 * 86400, "1 неделя"
            else:
                offset_sec, label = 86400, "1 день"

    # Number without unit → minutes (voice habit: "таймер на 5" ≈ 5 минут)
    if offset_sec is None:
        m = re.search(rf"(?:через\s+|на\s+|таймер\s+)({WORD_NUM_RE}|\d+)(?:\s|$)", p)
        if m:
            n = parse_word_number(m.group(1))
            if n is not None and n > 0:
                offset_sec, label = unit_to_seconds(n, "минут")

    if offset_sec is not None:
        due = now + timedelta(seconds=int(offset_sec))
        due = due.replace(microsecond=0)

    if due is None:
        # absolute-ish: завтра / в HH:MM
        day_offset = None
        if "послезавтра" in p:
            day_offset = 2
        elif "завтра" in p:
            day_offset = 1
        hour = minute = None
        m = re.search(r"(?:^|\s)в\s+(\d{1,2})[:\.\s]+(\d{2})(?:\s|$)", p)
        if m:
            hour, minute = int(m.group(1)), int(m.group(2))
        else:
            m = re.search(r"(?:^|\s)в\s+(\d{1,2})\s*(?:час|часа|часов)?(?:\s|$)", p)
            if m:
                hour, minute = int(m.group(1)), 0
        if day_offset is not None or hour is not None:
            base = now.replace(hour=0, minute=0, second=0, microsecond=0)
            if day_offset is not None:
                base = base + timedelta(days=day_offset)
            if hour is None:
                hour, minute = 9, 0
            due = base.replace(hour=hour, minute=minute or 0, second=0, microsecond=0)
            if day_offset is None and due <= now:
                due = due + timedelta(days=1)
            label = due.strftime("%d.%m %H:%M")

    if due is None:
        return None

    msg = p
    for pat in (
        r"через\s+полчаса",
        r"полчаса",
        r"через\s+полтора\s*час\w*",
        r"полтора\s*час\w*",
        rf"через\s+\d+\s*{UNIT_RE}",
        rf"на\s+\d+\s*{UNIT_RE}",
        rf"через\s+{WORD_NUM_RE}\s*{UNIT_RE}",
        rf"на\s+{WORD_NUM_RE}\s*{UNIT_RE}",
        rf"\d+\s*{UNIT_RE}",
        rf"{WORD_NUM_RE}\s*{UNIT_RE}",
        r"через\s+(?:секунд[уыа]|сек|минут[уыа]|мин|час(?:ик)?|день|дня|неделю)",
        r"на\s+(?:секунд[уыа]|сек|минут[уыа]|мин|час(?:ик)?|день|дня|неделю)",
        r"послезавтра",
        r"завтра",
        r"\bв\s+\d{1,2}[:\.\s]+\d{2}\b",
        r"\bв\s+\d{1,2}\s*(?:час|часа|часов)?\b",
        r"поставь таймер на",
        r"поставь таймер",
        r"запусти таймер на",
        r"запусти таймер",
        r"таймер на",
        r"таймер",
        r"напомни мне",
        r"напомни",
        r"напоминание",
        r"reminder",
        r"timer",
        r"set timer",
    ):
        msg = re.sub(pat, " ", msg, flags=re.I)
    msg = re.sub(r"\s+", " ", msg).strip(" .,:;-")
    if not msg:
        msg = f"Таймер: {label}" if label else "Таймер"
    return due, label, msg, offset_sec


def parse_delay_seconds(phrase: str) -> Optional[int]:
    parsed = parse_due(phrase)
    if not parsed:
        p = norm(phrase)
        if re.search(r"(^|\s)час(а|ов)?(\s|$)", p) and not re.search(r"\d|[а-я]+\s+час", p):
            return 3600
        return None
    due, _label, _msg, offset = parsed
    if offset is not None:
        return max(1, int(offset))
    sec = int(round((due - datetime.now()).total_seconds()))
    return max(1, sec)


def load_store() -> dict:
    path = reminders_path()
    if not path.exists():
        return {"items": []}
    try:
        raw = path.read_bytes()
        if raw.startswith(b"\xef\xbb\xbf"):
            raw = raw[3:]
        obj = json.loads(raw.decode("utf-8"))
        items = obj.get("items") or []
        if isinstance(items, dict):
            items = [items]
        return {"items": list(items)}
    except Exception:
        return {"items": []}


def save_store(store: dict) -> None:
    path = reminders_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    now = int(time.time())
    items = []
    for it in store.get("items") or []:
        # Drop ancient fired junk (keeps file clean, HUD readable)
        if it.get("fired") and int(it.get("due_unix") or 0) + 3600 < now:
            continue
        items.append(it)
    payload = {"items": items}
    tmp = path.with_suffix(f".{uuid.uuid4().hex}.tmp")
    tmp.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    tmp.replace(path)


def schedule_item(phrase: str, kind: str) -> int:
    parsed = parse_due(phrase)
    if not parsed:
        print("ERR:Не понял время. Пример: 5 минут / 2 часа / 30 секунд / завтра в 9", flush=True)
        return 2
    due, label, text, offset = parsed
    now_unix = int(time.time())
    if offset is not None:
        due_unix = now_unix + int(offset)
    else:
        due_unix = int(due.timestamp())
    if due_unix <= now_unix:
        print("ERR:Время уже прошло", flush=True)
        return 2
    kind = (kind or "timer").lower()
    if kind not in ("timer", "reminder"):
        kind = "timer" if ("таймер" in norm(phrase) or "timer" in norm(phrase)) else "reminder"
    leftover = (text or "").strip().lower()
    timeish = bool(
        leftover
        and (
            leftover
            in (
                "через",
                "на",
                "минуту",
                "минуты",
                "минут",
                "час",
                "часа",
                "часов",
                "секунду",
                "секунды",
                "секунд",
                "сек",
                "день",
                "дня",
                "дней",
            )
            or leftover.replace(" ", "").isdigit()
            or leftover.endswith(
                (
                    "секунд",
                    "секунды",
                    "секунду",
                    "сек",
                    "минут",
                    "минуты",
                    "минуту",
                    "мин",
                    "час",
                    "часа",
                    "часов",
                    "ч",
                )
            )
        )
    )
    if kind == "timer" and (not leftover or timeish):
        text = f"Таймер: {label}"
    elif not leftover or leftover in ("через", "на"):
        text = f"Напоминание: {label}"
    item_id = uuid.uuid4().hex[:12]
    store = load_store()
    store["items"] = [
        it
        for it in (store.get("items") or [])
        if (not it.get("fired")) or int(it.get("due_unix") or 0) + 3600 >= now_unix
    ]
    store["items"].append(
        {
            "id": item_id,
            "text": text,
            "due_unix": due_unix,
            "kind": kind,
            "fired": False,
        }
    )
    save_store(store)
    verify = load_store()
    ok = any(str(it.get("id")) == item_id and not it.get("fired") for it in verify.get("items") or [])
    if not ok:
        print("ERR:Не удалось сохранить таймер", flush=True)
        return 3
    when = datetime.fromtimestamp(due_unix).strftime("%d.%m.%Y %H:%M:%S")
    left = due_unix - now_unix
    print(f"OK:{kind}|{when}|{text}|{item_id}|{left}s", flush=True)
    return 0


def cancel_all() -> int:
    store = load_store()
    n = 0
    for it in store.get("items") or []:
        if not it.get("fired"):
            it["fired"] = True
            n += 1
    save_store(store)
    print(f"CANCELLED:{n}", flush=True)
    return 0


def cancel_one(item_id: str) -> int:
    item_id = (item_id or "").strip()
    if not item_id:
        print("ERR:missing_id", flush=True)
        return 2
    store = load_store()
    hit = False
    for it in store.get("items") or []:
        if str(it.get("id") or "") == item_id and not it.get("fired"):
            it["fired"] = True
            hit = True
            break
    if not hit:
        print("ERR:not_found", flush=True)
        return 2
    save_store(store)
    print("CANCELLED:1", flush=True)
    return 0


def reschedule_item(item_id: str, phrase: str) -> int:
    """Cancel one timer and create a new one with the given time phrase."""
    item_id = (item_id or "").strip()
    phrase = (phrase or "").strip()
    if not item_id or not phrase:
        print("ERR:missing_args", flush=True)
        return 2
    store = load_store()
    old = None
    for it in store.get("items") or []:
        if str(it.get("id") or "") == item_id and not it.get("fired"):
            old = it
            break
    if old is None:
        print("ERR:not_found", flush=True)
        return 2
    kind = str(old.get("kind") or "timer")
    # Keep reminder body if phrase is only a time expression
    body = ""
    if kind == "reminder":
        old_text = str(old.get("text") or "").strip()
        if old_text and not old_text.lower().startswith(("таймер:", "напоминание:")):
            body = old_text
    full = phrase
    if not re.search(r"(таймер|напомни|напоминание|timer|remind)", norm(full)):
        full = ("напомни " if kind == "reminder" else "таймер ") + phrase
    if body:
        full = f"{full} {body}"
    # mark old fired first so list stays clean even if schedule fails
    old["fired"] = True
    save_store(store)
    return schedule_item(full, kind)


def list_items(as_json: bool = False) -> int:
    store = load_store()
    pending = [it for it in store.get("items") or [] if not it.get("fired")]
    pending.sort(key=lambda x: int(x.get("due_unix") or 0))
    if as_json:
        out = []
        for it in pending:
            due = datetime.fromtimestamp(int(it.get("due_unix") or 0))
            out.append(
                {
                    "id": it.get("id"),
                    "text": it.get("text"),
                    "kind": it.get("kind"),
                    "due_unix": int(it.get("due_unix") or 0),
                    "due": due.strftime("%Y-%m-%d %H:%M:%S"),
                }
            )
        print(json.dumps(out, ensure_ascii=False), flush=True)
        return 0
    print(f"LIST:{len(pending)}", flush=True)
    for it in pending:
        due = datetime.fromtimestamp(int(it.get("due_unix") or 0))
        print(f"- [{it.get('kind')}] {it.get('text')} @ {due.strftime('%d.%m %H:%M')} #{it.get('id')}", flush=True)
    return 0


def shutdown_exe() -> str:
    root = os.environ.get("SystemRoot") or r"C:\Windows"
    p = Path(root) / "System32" / "shutdown.exe"
    return str(p) if p.exists() else "shutdown.exe"


def schedule_shutdown(seconds: int) -> int:
    seconds = max(0, min(int(seconds), 604800))
    exe = shutdown_exe()
    # clear previous
    subprocess.run([exe, "/a"], capture_output=True, text=True)
    time.sleep(0.15)
    msg = f"JARVIS: shutdown in {seconds} sec"
    r = subprocess.run([exe, "/s", "/t", str(seconds), "/c", msg], capture_output=True, text=True)
    # 1190 = already scheduled — retry once
    if r.returncode not in (0, None) and r.returncode != 0:
        subprocess.run([exe, "/a"], capture_output=True, text=True)
        time.sleep(0.2)
        r = subprocess.run([exe, "/s", "/t", str(seconds), "/c", msg], capture_output=True, text=True)
    h, rem = divmod(seconds, 3600)
    m, s = divmod(rem, 60)
    if h > 0:
        label = f"{h} ч {m} мин"
    elif m > 0:
        label = f"{m} мин"
    else:
        label = f"{s} сек"
    print(f"OK:shutdown|{seconds}|{label}", flush=True)
    return 0


def cancel_shutdown() -> int:
    exe = shutdown_exe()
    subprocess.run([exe, "/a"], capture_output=True, text=True)
    print("OK:cancelled", flush=True)
    return 0


def read_phrase(args: argparse.Namespace) -> str:
    if args.phrase_file:
        p = Path(args.phrase_file)
        if p.exists():
            text = p.read_text(encoding="utf-8-sig").strip()
            try:
                p.unlink()
            except Exception:
                pass
            return text
    return (args.phrase or "").strip()


def main(argv: Optional[list] = None) -> int:
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[attr-defined]
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[attr-defined]
    except Exception:
        pass

    p = argparse.ArgumentParser()
    p.add_argument(
        "action",
        choices=[
            "schedule",
            "cancel_all",
            "cancel_one",
            "reschedule",
            "list",
            "list_json",
            "shutdown",
            "shutdown_cancel",
            "parse_delay",
        ],
    )
    p.add_argument("--phrase", default="")
    p.add_argument("--phrase-file", default="")
    p.add_argument("--kind", default="auto", choices=["timer", "reminder", "auto"])
    p.add_argument("--seconds", type=int, default=0)
    p.add_argument("--id", default="")
    args = p.parse_args(argv)

    if args.action == "cancel_all":
        return cancel_all()
    if args.action == "cancel_one":
        return cancel_one(args.id)
    if args.action == "reschedule":
        return reschedule_item(args.id, read_phrase(args))
    if args.action == "list":
        return list_items(False)
    if args.action == "list_json":
        return list_items(True)
    if args.action == "shutdown_cancel":
        return cancel_shutdown()
    if args.action == "shutdown":
        sec = args.seconds
        if sec <= 0:
            phrase = read_phrase(args)
            parsed = parse_delay_seconds(phrase)
            if parsed is None:
                print("ERR:Не понял время. Пример: через 10 минут / через час / через 30 секунд", flush=True)
                return 2
            sec = parsed
        return schedule_shutdown(sec)
    if args.action == "parse_delay":
        phrase = read_phrase(args)
        sec = parse_delay_seconds(phrase)
        if sec is None:
            print("ERR:parse", flush=True)
            return 2
        print(f"OK:{sec}", flush=True)
        return 0

    # schedule timer/reminder
    phrase = read_phrase(args)
    if not phrase:
        print("ERR:Пустая фраза", flush=True)
        return 2
    kind = args.kind
    if kind == "auto":
        kind = "timer" if ("таймер" in norm(phrase) or "timer" in norm(phrase)) else "reminder"
    return schedule_item(phrase, kind)


if __name__ == "__main__":
    raise SystemExit(main())
