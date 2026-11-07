# -*- coding: utf-8 -*-
from pathlib import Path

root = Path(__file__).resolve().parents[4] / "resources" / "commands"
old_ru = 'sounds.ru = ["ok1", "ok2", "ok3"]'
new_ru = 'sounds.ru = ["ok1", "ok2", "ok3", "ok4", "ok5"]'
old_en = 'sounds.en = ["ok1", "ok2", "ok3"]'
new_en = 'sounds.en = ["ok1", "ok2", "ok3", "ok4", "ok5"]'
n = 0
for p in root.rglob("command.toml"):
    t = p.read_text(encoding="utf-8")
    nt = t.replace(old_ru, new_ru).replace(old_en, new_en)
    if nt != t:
        p.write_text(nt, encoding="utf-8")
        n += 1
print("updated", n, "files")
