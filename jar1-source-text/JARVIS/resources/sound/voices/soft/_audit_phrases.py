# -*- coding: utf-8 -*-
import re
from pathlib import Path

p = Path(r"C:\jarvisTOP\resources\commands\popular\command.toml")
text = p.read_text(encoding="utf-8")
blocks = re.split(r"\n\[\[commands\]\]\n", text)
latin = re.compile(r"[a-zA-Z]{2,}")
eng_in_ru = []
shortish = []
bare_single = []
for b in blocks[1:]:
    mid = re.search(r'id\s*=\s*"([^"]+)"', b)
    if not mid:
        continue
    cid = mid.group(1)
    m = re.search(r"phrases\.ru\s*=\s*\[(.*?)\]", b, re.S)
    if not m:
        continue
    phrases = re.findall(r'"([^"]+)"', m.group(1))
    for ph in phrases:
        words = ph.split()
        if latin.search(ph):
            eng_in_ru.append((cid, ph))
        if len(words) == 1:
            bare_single.append((cid, ph, len(ph)))
        if len(words) == 1 and len(ph) <= 8:
            shortish.append((cid, ph, len(ph)))

out = Path(__file__).with_name("_audit_out.txt")
lines = ["=== ENGLISH IN phrases.ru ==="]
for x in eng_in_ru:
    lines.append(f"{x[0]}\t{x[1]}")
lines.append("=== SHORT single-word <=8 ===")
for x in sorted(shortish, key=lambda t: (len(t[1]), t[0])):
    lines.append(f"{x[0]}\t{x[1]}")
lines.append("=== ALL bare single-word ===")
for x in sorted(bare_single, key=lambda t: (len(t[1]), t[0])):
    lines.append(f"{x[0]}\t{x[1]}")
out.write_text("\n".join(lines), encoding="utf-8")
print("wrote", out, "eng", len(eng_in_ru), "short", len(shortish), "bare", len(bare_single))
