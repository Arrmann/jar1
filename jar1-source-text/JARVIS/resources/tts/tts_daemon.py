#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Persistent Silero TTS daemon for JARVIS background mode.

Loads v5_5_ru (or v5_ru) once, then processes jobs from:
  <JARVIS data dir>/tts-worker/inbox/<id>.json
"""
from __future__ import annotations

import json
import os
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

import speak as tts  # noqa: E402


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


def worker_dir() -> Path:
    d = data_dir() / "tts-worker"
    d.mkdir(parents=True, exist_ok=True)
    (d / "inbox").mkdir(parents=True, exist_ok=True)
    return d


def write_heartbeat(path: Path) -> None:
    try:
        path.write_text(str(int(time.time())), encoding="ascii")
    except OSError:
        pass


def process_job(model, job: dict) -> None:
    job_id = str(job.get("id") or "")
    text = str(job.get("text") or "")
    voice = str(job.get("voice") or tts.DEFAULT_VOICE)
    if voice not in tts.VOICES:
        voice = tts.DEFAULT_VOICE
    speed = float(job.get("speed") or 1.0)
    speed = max(0.5, min(2.0, speed))
    out_dir = Path(str(job.get("out_dir") or ""))
    stop_file = Path(str(job.get("stop_file") or "")) if job.get("stop_file") else None
    max_words = int(job.get("max_words") or tts.MAX_WORDS)
    sample_rate = int(job.get("sample_rate") or tts.SAMPLE_RATE)
    if sample_rate not in (8000, 24000, 48000):
        sample_rate = tts.SAMPLE_RATE
    inbox = worker_dir() / "inbox"
    done_path = inbox / f"{job_id}.done"
    err_path = inbox / f"{job_id}.error"

    try:
        text = tts.normalize_text(text)
        text = tts.limit_words(text, max(100, max_words))
        chunks = tts.split_chunks(text)
        if not chunks:
            raise RuntimeError("empty text")
        out_dir.mkdir(parents=True, exist_ok=True)
        started_at = time.time()
        for i, chunk in enumerate(chunks, start=1):
            if tts.should_stop(stop_file, started_at=started_at):
                break
            audio = tts.synthesize_chunk(model, chunk, voice, sample_rate, speed)
            wav_path = out_dir / f"chunk_{i:04d}.wav"
            tts.write_wav(wav_path, audio, sample_rate)
        done_path.write_text("ok", encoding="utf-8")
    except Exception as ex:  # noqa: BLE001
        try:
            err_path.write_text(f"{type(ex).__name__}: {ex}", encoding="utf-8")
        except OSError:
            pass
        try:
            done_path.write_text("error", encoding="utf-8")
        except OSError:
            pass


def main() -> int:
    import argparse

    parser = argparse.ArgumentParser(description="JARVIS Silero TTS background daemon")
    parser.add_argument("--model", default="", help="Path to v5_5_ru.pt / v5_ru.pt")
    args = parser.parse_args()

    model_path = Path(args.model) if args.model else tts.default_model_path()
    if not model_path.is_file():
        model_path = tts.default_model_path()
    if not model_path.is_file():
        print(f"Model not found: {model_path}", file=sys.stderr)
        return 3

    wd = worker_dir()
    pid_file = data_dir() / "tts.worker.pid"
    alive_file = wd / "alive"
    shutdown_file = wd / "shutdown"
    inbox = wd / "inbox"

    try:
        shutdown_file.unlink(missing_ok=True)
    except TypeError:
        if shutdown_file.exists():
            shutdown_file.unlink()

    pid_file.write_text(str(os.getpid()), encoding="ascii")
    print(f"TTS daemon starting pid={os.getpid()} model={model_path}", flush=True)

    model, _ = tts.load_model(model_path)
    print("TTS daemon ready", flush=True)

    while True:
        if shutdown_file.exists():
            break
        write_heartbeat(alive_file)
        jobs = sorted(inbox.glob("*.json"))
        for job_path in jobs:
            done = inbox / f"{job_path.stem}.done"
            err = inbox / f"{job_path.stem}.error"
            if done.exists() or err.exists():
                continue
            try:
                job = json.loads(job_path.read_text(encoding="utf-8"))
            except Exception as ex:  # noqa: BLE001
                try:
                    err.write_text(str(ex), encoding="utf-8")
                    done.write_text("error", encoding="utf-8")
                except OSError:
                    pass
                continue
            process_job(model, job)
            try:
                job_path.unlink(missing_ok=True)
            except TypeError:
                if job_path.exists():
                    job_path.unlink()
        time.sleep(0.15)

    try:
        pid_file.unlink(missing_ok=True)
    except TypeError:
        if pid_file.exists():
            pid_file.unlink()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
