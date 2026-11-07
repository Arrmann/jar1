# -*- coding: utf-8 -*-
from pathlib import Path
import re

p = Path(__file__).with_name("_gen_phrases.py").read_text(encoding="utf-8")
keys = set(re.findall(r'"(cmd_[^"]+)"', p))
files = {x.stem for x in Path(__file__).resolve().parents[1].joinpath("mita", "ru").glob("cmd_*.mp3")}
print("mita cmds", len(files))
print("CONFIRM keys", len(keys))
print("missing CONFIRM:")
for x in sorted(files - keys):
    print(" ", x)
print("extra CONFIRM (not in mita):")
for x in sorted(keys - files):
    print(" ", x)
