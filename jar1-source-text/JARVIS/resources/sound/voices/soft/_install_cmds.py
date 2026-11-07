# -*- coding: utf-8 -*-
"""Map Fish Downloads mp3 -> soft/ru/cmd_*.mp3 by phrase text in filename."""
from __future__ import annotations

import re
import shutil
from pathlib import Path

SRC = Path(r"C:\Users\Мирослав\Downloads")
DST = Path(__file__).resolve().parent / "ru"
GEN = Path(__file__).resolve().parent / "_gen_phrases.py"
MITA = Path(__file__).resolve().parents[1] / "mita" / "ru"
DST.mkdir(parents=True, exist_ok=True)

# Parse CONFIRM dict literally from generator source
_src = GEN.read_text(encoding="utf-8")
CONFIRM: dict[str, str] = dict(
    re.findall(r'"((?:cmd_)[^"]+)":\s*"([^"]*)"', _src)
)


def norm(s: str) -> str:
    s = s.lower().replace("ё", "е")
    s = s.replace("'", "").replace("’", "").replace("`", "")
    s = re.sub(r"[^a-zа-я0-9]+", "", s)
    return s


def phrase_from_name(name: str) -> str:
    m = re.search(r"\)-(.+)\.mp3$", name, re.I)
    if not m:
        return ""
    return m.group(1).replace("-", " ").replace("!", "").strip()


def main() -> None:
    # Soft pack list (CONFIRM) — date/time intentionally omitted.
    cmds = sorted(CONFIRM.keys())
    by_text: dict[str, str] = {}
    for stem, text in CONFIRM.items():
        by_text[norm(text)] = stem

    files = sorted(SRC.glob("Спокойный-2026-10-17*.mp3"))
    matched: list[tuple[str, str]] = []
    unmatched: list[tuple[str, str]] = []
    used: set[str] = set()

    # Prefer longer needles first when matching truncated names
    text_keys = sorted(by_text.keys(), key=len, reverse=True)

    for f in files:
        phrase = phrase_from_name(f.name)
        key = norm(phrase)
        if not key:
            unmatched.append((f.name, "empty"))
            continue
        stem = by_text.get(key)
        if not stem:
            for t in text_keys:
                if t.startswith(key) or key.startswith(t):
                    # avoid tiny keys matching everything
                    if len(key) < 6 and len(t) > len(key) + 4:
                        continue
                    stem = by_text[t]
                    break
        if not stem:
            unmatched.append((f.name, phrase))
            continue
        if stem in used and stem.startswith("cmd_"):
            unmatched.append((f.name, f"dup->{stem}"))
            continue
        shutil.copy2(f, DST / f"{stem}.mp3")
        used.add(stem)
        matched.append((stem, f.name))

    present = [c for c in cmds if (DST / f"{c}.mp3").exists()]
    missing = [c for c in cmds if not (DST / f"{c}.mp3").exists()]

    report = Path(__file__).resolve().parent / "INSTALL_REPORT.txt"
    report.write_text(
        "\n".join(
            [
                f"cmd {len(present)}/{len(cmds)}",
                "",
                "MISSING:",
                *[f"{m}\t{CONFIRM.get(m,'')}" for m in missing],
                "",
                "UNMATCHED:",
                *[f"{a}\t{b}" for a, b in unmatched],
                "",
                "MATCHED:",
                *[f"{a}\t{b}" for a, b in matched],
            ]
        ),
        encoding="utf-8",
    )
    print(f"scanned={len(files)} matched={len(matched)} cmd={len(present)}/{len(cmds)} missing={len(missing)}")
    print("report:", report)
    for m in missing:
        print("MISSING", m)


if __name__ == "__main__":
    main()
