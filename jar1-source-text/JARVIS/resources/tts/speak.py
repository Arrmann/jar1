#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Offline Silero TTS worker for JARVIS.

Uses the highest-quality Russian package available locally:
  models/v5_5_ru.pt  (preferred) → models/v5_ru.pt (fallback).
Speakers: aidar, baya, kseniya, xenia, eugene.
Default sample rate 48000 for max quality.
"""
from __future__ import annotations

import argparse
import os
import re
import sys
import time
import wave
from pathlib import Path


VOICES = ("aidar", "baya", "kseniya", "xenia", "eugene")
DEFAULT_VOICE = "aidar"
SAMPLE_RATE = 48000
MAX_WORDS = 6000
MAX_CHUNK_CHARS = 700

ROOT = Path(__file__).resolve().parent


def eprint(*args: object) -> None:
    print(*args, file=sys.stderr, flush=True)


def should_stop(stop_file: Path | None, *, started_at: float | None = None) -> bool:
    """True only if stop_file appears/changes AFTER this process started (ignore stale Esc flags)."""
    if stop_file is None:
        return False
    try:
        if not stop_file.exists():
            return False
        if started_at is None:
            return True
        # Honor only a fresh write (Esc / cancel during this run).
        return stop_file.stat().st_mtime >= (started_at - 0.05)
    except OSError:
        return False


_ONES = (
    "ноль",
    "один",
    "два",
    "три",
    "четыре",
    "пять",
    "шесть",
    "семь",
    "восемь",
    "девять",
)
_ONES_F = (
    "ноль",
    "одна",
    "две",
    "три",
    "четыре",
    "пять",
    "шесть",
    "семь",
    "восемь",
    "девять",
)
_TEENS = (
    "десять",
    "одиннадцать",
    "двенадцать",
    "тринадцать",
    "четырнадцать",
    "пятнадцать",
    "шестнадцать",
    "семнадцать",
    "восемнадцать",
    "девятнадцать",
)
_TENS = (
    "",
    "десять",
    "двадцать",
    "тридцать",
    "сорок",
    "пятьдесят",
    "шестьдесят",
    "семьдесят",
    "восемьдесят",
    "девяносто",
)
_HUNDREDS = (
    "",
    "сто",
    "двести",
    "триста",
    "четыреста",
    "пятьсот",
    "шестьсот",
    "семьсот",
    "восемьсот",
    "девятьсот",
)
_MONTHS = (
    "",
    "января",
    "февраля",
    "марта",
    "апреля",
    "мая",
    "июня",
    "июля",
    "августа",
    "сентября",
    "октября",
    "ноября",
    "декабря",
)


def _triad(n: int, feminine: bool = False) -> str:
    if n <= 0:
        return ""
    ones = _ONES_F if feminine else _ONES
    parts: list[str] = []
    h, rem = divmod(n, 100)
    if h:
        parts.append(_HUNDREDS[h])
    if 10 <= rem <= 19:
        parts.append(_TEENS[rem - 10])
    else:
        t, o = divmod(rem, 10)
        if t:
            parts.append(_TENS[t])
        if o:
            parts.append(ones[o])
    return " ".join(parts)


def number_to_words(n: int, feminine: bool = False) -> str:
    if n < 0:
        return "минус " + number_to_words(-n, feminine)
    if n == 0:
        return "ноль"
    if n > 999_999_999:
        return " ".join(_ONES[int(ch)] for ch in str(n))

    parts: list[str] = []
    millions, rem = divmod(n, 1_000_000)
    if millions:
        parts.append(_triad(millions, False))
        if millions % 10 == 1 and millions % 100 != 11:
            parts.append("миллион")
        elif millions % 10 in (2, 3, 4) and millions % 100 not in (12, 13, 14):
            parts.append("миллиона")
        else:
            parts.append("миллионов")
    thousands, rem = divmod(rem, 1000)
    if thousands:
        parts.append(_triad(thousands, True))
        if thousands % 10 == 1 and thousands % 100 != 11:
            parts.append("тысяча")
        elif thousands % 10 in (2, 3, 4) and thousands % 100 not in (12, 13, 14):
            parts.append("тысячи")
        else:
            parts.append("тысяч")
    if rem:
        parts.append(_triad(rem, feminine))
    return " ".join(p for p in parts if p)


def _rub_form(n: int) -> str:
    n = abs(n) % 100
    if 11 <= n <= 14:
        return "рублей"
    r = n % 10
    if r == 1:
        return "рубль"
    if r in (2, 3, 4):
        return "рубля"
    return "рублей"


def _day_words(day: int) -> str:
    # Ordinal-ish genitive for TTS: «двенадцатое»
    base = number_to_words(day, feminine=True)
    # Soft heuristic endings for common days
    mapping = {
        1: "первое",
        2: "второе",
        3: "третье",
        4: "четвёртое",
        5: "пятое",
        6: "шестое",
        7: "седьмое",
        8: "восьмое",
        9: "девятое",
        10: "десятое",
        11: "одиннадцатое",
        12: "двенадцатое",
        13: "тринадцатое",
        14: "четырнадцатое",
        15: "пятнадцатое",
        16: "шестнадцатое",
        17: "семнадцатое",
        18: "восемнадцатое",
        19: "девятнадцатое",
        20: "двадцатое",
        30: "тридцатое",
    }
    if day in mapping:
        return mapping[day]
    if 21 <= day <= 29:
        return "двадцать " + mapping[day - 20]
    if day == 31:
        return "тридцать первое"
    return base


def _year_words(year: int) -> str:
    if 2000 <= year <= 2099:
        rem = year - 2000
        if rem == 0:
            return "две тысячи года"
        return "две тысячи " + number_to_words(rem, feminine=True) + " года"
    return number_to_words(year) + " года"


def expand_for_speech(text: str) -> str:
    """Make numbers/dates/abbreviations speakable for Silero (no extra deps)."""
    # Drop bare URLs / emails — neural TTS mangles them.
    text = re.sub(r"https?://\S+", " ссылка ", text, flags=re.IGNORECASE)
    text = re.sub(r"\b[\w.\-+]+@[\w.\-]+\.\w+\b", " электронная почта ", text)

    def _date(m: re.Match[str]) -> str:
        d, mo, y = int(m.group(1)), int(m.group(2)), int(m.group(3))
        if not (1 <= d <= 31 and 1 <= mo <= 12 and 1900 <= y <= 2100):
            return m.group(0)
        return f"{_day_words(d)} {_MONTHS[mo]} {_year_words(y)}"

    text = re.sub(r"\b(\d{1,2})[./](\d{1,2})[./](\d{4})\b", _date, text)

    def _money(m: re.Match[str]) -> str:
        n = int(m.group(1).replace(" ", ""))
        return f"{number_to_words(n)} {_rub_form(n)}"

    text = re.sub(
        r"\b(\d[\d\s]{0,12})\s*(?:руб\.?|₽|RUB)\b",
        _money,
        text,
        flags=re.IGNORECASE,
    )

    def _plain_num(m: re.Match[str]) -> str:
        raw = m.group(0)
        if len(raw) > 9:
            return " ".join(_ONES[int(ch)] for ch in raw)
        try:
            return number_to_words(int(raw))
        except ValueError:
            return raw

    text = re.sub(r"\b\d{1,9}\b", _plain_num, text)

    replacements = (
        (r"(?i)\bи\s*т\.?\s*д\.?", "и так далее"),
        (r"(?i)\bи\s*т\.?\s*п\.?", "и тому подобное"),
        (r"(?i)\bт\.?\s*д\.?", "так далее"),
        (r"(?i)\bт\.?\s*е\.?", "то есть"),
        (r"(?i)\bт\.?\s*п\.?", "тому подобное"),
        (r"(?i)\bдр\.", "другие"),
        (r"(?i)\bг\.", "год"),
        (r"(?i)\bул\.", "улица"),
        (r"(?i)\bпр-т\b", "проспект"),
        (r"%", " процентов "),
        (r"№", " номер "),
    )
    for pat, rep in replacements:
        text = re.sub(pat, rep, text)

    return text


def normalize_text(text: str) -> str:
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    text = expand_for_speech(text)
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    text = text.strip()
    # Silero RU v5 yields empty audio on Latin-only input (URLs, English clipboard).
    if text and not re.search(r"[А-Яа-яЁё]", text):
        text = "Читаю. " + text
    if not text:
        text = "Пустой текст"
    return text


def limit_words(text: str, max_words: int) -> str:
    words = re.findall(r"\S+", text)
    if len(words) <= max_words:
        return text
    parts = re.split(r"(\s+)", text)
    count = 0
    out: list[str] = []
    for part in parts:
        if part.strip():
            count += 1
            if count > max_words:
                break
        out.append(part)
    return "".join(out).strip()


def split_chunks(text: str, max_chars: int = MAX_CHUNK_CHARS) -> list[str]:
    text = normalize_text(text)
    if not text:
        return []
    pieces = re.split(r"(?<=[\.!\?;…])\s+|\n+", text)
    chunks: list[str] = []
    buf = ""
    for piece in pieces:
        piece = piece.strip()
        if not piece:
            continue
        if not buf:
            buf = piece
        elif len(buf) + 1 + len(piece) <= max_chars:
            buf = f"{buf} {piece}"
        else:
            chunks.append(buf)
            buf = piece
        while len(buf) > max_chars:
            cut = buf.rfind(" ", 0, max_chars)
            if cut < max_chars // 3:
                cut = max_chars
            chunks.append(buf[:cut].strip())
            buf = buf[cut:].strip()
    if buf:
        chunks.append(buf)
    return [c for c in chunks if c]


def apply_speed(audio, speed: float):
    import numpy as np

    if abs(speed - 1.0) < 0.02:
        return audio
    speed = max(0.5, min(2.0, float(speed)))
    x = audio.detach().cpu().numpy() if hasattr(audio, "detach") else audio
    x = np.asarray(x, dtype=np.float32).reshape(-1)
    n = int(len(x) / speed)
    if n < 16:
        return x
    idx = np.linspace(0, len(x) - 1, n).astype(np.float64)
    i0 = np.floor(idx).astype(np.int64)
    i1 = np.minimum(i0 + 1, len(x) - 1)
    t = idx - i0
    y = x[i0] * (1.0 - t) + x[i1] * t
    return y.astype(np.float32)


def write_wav(path: Path, audio, sample_rate: int) -> None:
    import numpy as np

    x = audio.detach().cpu().numpy() if hasattr(audio, "detach") else audio
    x = np.asarray(x, dtype=np.float32).reshape(-1)
    x = np.clip(x, -1.0, 1.0)
    pcm = (x * 32767.0).astype("<i2")
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sample_rate)
        wf.writeframes(pcm.tobytes())


def default_model_path() -> Path:
    for name in ("v5_5_ru.pt", "v5_ru.pt"):
        p = ROOT / "models" / name
        if p.is_file() and p.stat().st_size > 1_000_000:
            return p
    return ROOT / "models" / "v5_5_ru.pt"


def load_model(model_path: Path):
    import torch

    torch.set_num_threads(max(1, min(4, os.cpu_count() or 2)))
    device = torch.device("cpu")
    model = torch.package.PackageImporter(str(model_path)).load_pickle(
        "tts_models", "model"
    )
    model.to(device)
    return model, device


def synthesize_chunk(model, text: str, speaker: str, sample_rate: int, speed: float):
    if isinstance(model, tuple):
        model = model[0]
    # Silero RU v5 raises empty ValueError on Latin-only / empty phoneme input.
    if not re.search(r"[А-Яа-яЁё]", text or ""):
        raise RuntimeError(
            "Silero RU needs Cyrillic text (Latin-only input is rejected by the model)"
        )
    try:
        audio = model.apply_tts(
            text=text,
            speaker=speaker,
            sample_rate=sample_rate,
            put_accent=True,
            put_yo=True,
        )
    except Exception as first:
        soft = re.sub(r"[^\w\s\.\!\?\;\:\,\-\—\–«»\"'()]", " ", text, flags=re.UNICODE)
        soft = re.sub(r"\s+", " ", soft).strip()
        if not soft or soft == text:
            raise RuntimeError(f"Silero apply_tts failed: {type(first).__name__}: {first}") from first
        try:
            audio = model.apply_tts(
                text=soft,
                speaker=speaker,
                sample_rate=sample_rate,
                put_accent=True,
                put_yo=True,
            )
        except Exception as second:
            raise RuntimeError(
                f"Silero apply_tts failed: {type(second).__name__}: {second}"
            ) from second
    return apply_speed(audio, speed)


SERVE_TAG = "@@jarvis "


def _serve_emit(line: str) -> None:
    sys.stdout.write(SERVE_TAG + line.replace("\n", " ").replace("\r", " ") + "\n")
    sys.stdout.flush()


def _serve_job(model, job: dict) -> None:
    import numpy as np

    out = Path(str(job.get("out") or ""))
    voice = str(job.get("voice") or DEFAULT_VOICE)
    if voice not in VOICES:
        voice = DEFAULT_VOICE
    speed = max(0.5, min(2.0, float(job.get("speed") or 1.0)))
    sample_rate = int(job.get("sample_rate") or SAMPLE_RATE)
    if sample_rate not in (8000, 24000, 48000):
        sample_rate = SAMPLE_RATE
    stop_file = Path(str(job["stop_file"])) if job.get("stop_file") else None
    started_at = time.time()

    text = limit_words(normalize_text(str(job.get("text") or "")), MAX_WORDS)
    parts = []
    for chunk in split_chunks(text):
        if should_stop(stop_file, started_at=started_at):
            raise RuntimeError("stopped")
        audio = synthesize_chunk(model, chunk, voice, sample_rate, speed)
        x = audio.detach().cpu().numpy() if hasattr(audio, "detach") else audio
        parts.append(np.asarray(x, dtype=np.float32).reshape(-1))
    if not parts:
        raise RuntimeError("empty text")
    write_wav(out, np.concatenate(parts), sample_rate)


def serve(model_path: Path, idle_exit: float) -> int:
    """Keep the model loaded; one JSON job per stdin line, one tagged reply per job."""
    import json
    import queue
    import threading

    t0 = time.time()
    model, _device = load_model(model_path)
    try:
        # First apply_tts is several times slower (lazy init) — pay it before READY.
        synthesize_chunk(model, "Готов.", DEFAULT_VOICE, SAMPLE_RATE, 1.0)
    except Exception as ex:  # noqa: BLE001
        eprint(f"warmup failed: {ex}")
    _serve_emit(f"READY {time.time() - t0:.1f}")

    lines: "queue.Queue[bytes | None]" = queue.Queue()

    def pump() -> None:
        for raw in sys.stdin.buffer:
            lines.put(raw)
        lines.put(None)

    threading.Thread(target=pump, daemon=True).start()
    while True:
        try:
            raw = lines.get(timeout=idle_exit if idle_exit > 0 else None)
        except queue.Empty:
            return 0
        if raw is None:
            return 0
        try:
            job = json.loads(raw.decode("utf-8", errors="replace"))
        except ValueError:
            continue
        job_id = str(job.get("id") or "")
        try:
            _serve_job(model, job)
            _serve_emit(f"OK {job_id}")
        except Exception as ex:  # noqa: BLE001
            _serve_emit(f"ERR {job_id} {type(ex).__name__}: {ex}")


def main() -> int:
    parser = argparse.ArgumentParser(description="JARVIS Silero TTS worker")
    parser.add_argument("--text", default="", help="Text to speak")
    parser.add_argument("--text-file", default="", help="UTF-8 text file")
    parser.add_argument("--out", default="", help="Output WAV path (or dir with --stream)")
    parser.add_argument("--voice", default=DEFAULT_VOICE, choices=VOICES)
    parser.add_argument("--speed", type=float, default=1.0)
    parser.add_argument("--sample-rate", type=int, default=SAMPLE_RATE)
    parser.add_argument("--model", default="", help="Path to v5_5_ru.pt / v5_ru.pt")
    parser.add_argument("--stop-file", default="", help="If this file appears, abort")
    parser.add_argument("--max-words", type=int, default=MAX_WORDS)
    parser.add_argument(
        "--stream",
        action="store_true",
        help="Write chunk_0001.wav ... into --out directory and print READY lines",
    )
    parser.add_argument("--list-voices", action="store_true")
    parser.add_argument(
        "--serve",
        action="store_true",
        help="Persistent mode: JSON jobs on stdin, tagged replies on stdout",
    )
    parser.add_argument("--idle-exit", type=float, default=0.0, help="--serve: exit after N idle seconds")
    args = parser.parse_args()

    if args.list_voices:
        print(",".join(VOICES))
        return 0

    model_path = Path(args.model) if args.model else default_model_path()
    if args.serve:
        if not model_path.is_file():
            eprint(f"Model not found: {model_path}")
            return 3
        return serve(model_path, float(args.idle_exit))
    if not args.out:
        eprint("--out is required")
        return 2
    stop_file = Path(args.stop_file) if args.stop_file else None
    started_at = time.time()

    text = args.text or ""
    if args.text_file:
        text = Path(args.text_file).read_text(encoding="utf-8")
    if not text and not sys.stdin.isatty():
        text = sys.stdin.read()
    text = normalize_text(text)
    if not text:
        eprint("No text provided")
        return 2

    text = limit_words(text, max(100, int(args.max_words)))
    chunks = split_chunks(text)
    if not chunks:
        eprint("Empty after normalize")
        return 2

    if should_stop(stop_file, started_at=started_at):
        eprint("Stopped before start")
        return 0

    if not model_path.is_file():
        eprint(f"Model not found: {model_path}")
        return 3

    voice = args.voice if args.voice in VOICES else DEFAULT_VOICE
    speed = max(0.5, min(2.0, float(args.speed)))
    sample_rate = int(args.sample_rate)
    if sample_rate not in (8000, 24000, 48000):
        sample_rate = SAMPLE_RATE

    word_n = len(re.findall(r"\S+", text))
    eprint(
        f"Silero load model={model_path.name} voice={voice} speed={speed} "
        f"sr={sample_rate} chunks={len(chunks)} words~{word_n}"
    )
    t0 = time.time()
    model, _device = load_model(model_path)
    eprint(f"Model ready in {time.time() - t0:.1f}s")

    out = Path(args.out)
    if args.stream:
        out.mkdir(parents=True, exist_ok=True)
        for i, chunk in enumerate(chunks, start=1):
            if should_stop(stop_file, started_at=started_at):
                eprint("Stopped by flag")
                print("STOPPED", flush=True)
                return 0
            wav_path = out / f"chunk_{i:04d}.wav"
            try:
                audio = synthesize_chunk(model, chunk, voice, sample_rate, speed)
                write_wav(wav_path, audio, sample_rate)
            except Exception as ex:  # noqa: BLE001
                eprint(f"Chunk {i} failed: {ex}")
                continue
            print(f"READY {wav_path}", flush=True)
        print("DONE", flush=True)
        return 0

    import numpy as np

    parts = []
    for i, chunk in enumerate(chunks, start=1):
        if should_stop(stop_file, started_at=started_at):
            eprint("Stopped by flag")
            break
        try:
            audio = synthesize_chunk(model, chunk, voice, sample_rate, speed)
            x = audio.detach().cpu().numpy() if hasattr(audio, "detach") else audio
            parts.append(np.asarray(x, dtype=np.float32).reshape(-1))
        except Exception as ex:  # noqa: BLE001
            eprint(f"Chunk {i} failed: {ex}")
    if not parts:
        return 4
    merged = np.concatenate(parts)
    write_wav(out, merged, sample_rate)
    print(str(out), flush=True)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(0)
