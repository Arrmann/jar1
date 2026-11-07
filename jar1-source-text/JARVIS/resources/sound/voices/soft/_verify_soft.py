# -*- coding: utf-8 -*-
"""Meticulous Soft pack + phrase audit."""
from __future__ import annotations

import re
from pathlib import Path

SOFT = Path(__file__).resolve().parent
RU = SOFT / "ru"
GEN = SOFT / "_gen_phrases.py"
POP = Path(r"C:\jarvisTOP\resources\commands\popular\command.toml")
CTRL = Path(r"C:\jarvisTOP\resources\commands\control\command.toml")
OUT = SOFT / "VERIFY_REPORT.txt"

src = GEN.read_text(encoding="utf-8")
confirm = dict(re.findall(r'"((?:cmd_)[^"]+)":\s*"([^"]*)"', src))
assert "cmd_what_date" not in confirm
assert "cmd_what_time" not in confirm

lines: list[str] = []
missing = [c for c in confirm if not (RU / f"{c}.mp3").exists()]
extra = sorted(
    p.stem
    for p in RU.glob("cmd_*.mp3")
    if p.stem not in confirm and p.stem not in ("cmd_what_date", "cmd_what_time")
)
tiny = sorted(
    f"{p.stem}\t{p.stat().st_size}"
    for p in RU.glob("cmd_*.mp3")
    if p.stat().st_size < 5000
)

lines.append(f"CONFIRM cmds: {len(confirm)}")
lines.append(f"installed cmd_*.mp3: {len(list(RU.glob('cmd_*.mp3')))}")
lines.append(f"MISSING: {len(missing)}")
lines.extend(f"  {m}" for m in missing)
lines.append(f"EXTRA: {len(extra)}")
lines.extend(f"  {e}" for e in extra)
lines.append(f"TINY(<5k): {len(tiny)}")
lines.extend(f"  {t}" for t in tiny)

# reactions required by voice.toml
voice = (SOFT / "voice.toml").read_text(encoding="utf-8")
react_ids = re.findall(r'\[\s*"([^"]+)"\s*\]', voice)
# also multi: ["a","b"]
react_ids = re.findall(r'"([a-z0-9_]+)"', voice.split("[reactions.ru]")[1].split("[")[0])
react_missing = [r for r in react_ids if not (RU / f"{r}.mp3").exists()]
lines.append(f"reactions expected: {len(react_ids)} missing: {len(react_missing)}")
lines.extend(f"  {r}" for r in react_missing)

latin = re.compile(r"[a-zA-Z]{2,}")
# ignore intentional latin-free check exceptions: none
for label, path in (("popular", POP), ("control", CTRL)):
    text = path.read_text(encoding="utf-8")
    blocks = re.split(r"\n\[\[commands\]\]\n", text)
    eng = []
    short_common = []
    BAD_BARE = {
        "назад",
        "вперёд",
        "вперед",
        "погода",
        "новости",
        "звук",
        "громкость",
        "яркость",
        "найди",
        "поиск",
        "обновить",
        "клик",
        "ввод",
        "зум",
        "обс",
        "иви",
        "мит",
    }
    for b in blocks[1:]:
        mid = re.search(r'id\s*=\s*"([^"]+)"', b)
        if not mid:
            continue
        cid = mid.group(1)
        m = re.search(r"phrases\.ru\s*=\s*\[(.*?)\]", b, re.S)
        if not m:
            continue
        for ph in re.findall(r'"([^"]+)"', m.group(1)):
            if latin.search(ph) and not re.search(r"[а-яА-Я]", ph):
                # pure latin phrases in .ru — bad for Vosk
                eng.append((cid, ph))
            elif latin.search(ph):
                eng.append((cid, ph))
            if ph in BAD_BARE:
                short_common.append((cid, ph))
    lines.append(f"{label} EN-in-ru: {len(eng)}")
    lines.extend(f"  {a}\t{b}" for a, b in eng[:80])
    lines.append(f"{label} bad-bare: {len(short_common)}")
    lines.extend(f"  {a}\t{b}" for a, b in short_common)

# rutube phrases present
pop = POP.read_text(encoding="utf-8")
m = re.search(r'id\s*=\s*"open_rutube".*?phrases\.ru\s*=\s*\[(.*?)\]', pop, re.S)
rutube_ph = re.findall(r'"([^"]+)"', m.group(1)) if m else []
lines.append("open_rutube phrases:")
lines.extend(f"  {p}" for p in rutube_ph)
need = {"открой рутуб", "рутуб", "открой рот", "рот убы"}
lines.append(f"rutube need ok: {need.issubset(set(rutube_ph))}")

# key file sizes for user’s downloads set
key = [
    "cmd_open_rutube",
    "cmd_browser_downloads",
    "cmd_open_translate",
    "cmd_open_downloads",
    "cmd_translate",
    "cmd_brightness_down",
    "cmd_volume_up",
]
lines.append("KEY FILES:")
for k in key:
    p = RU / f"{k}.mp3"
    lines.append(f"  {k}\t{'OK' if p.exists() else 'MISS'}\t{p.stat().st_size if p.exists() else 0}")

OUT.write_text("\n".join(lines), encoding="utf-8")
print("wrote", OUT)
print("missing", len(missing), "eng_popular_hint in report")
print("rutube", rutube_ph)
