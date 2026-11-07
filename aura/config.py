import copy
import json
import os
from pathlib import Path
from typing import Any


DEFAULT_CONFIG = {
    "language": "ru",
    "theme": "dark",
    "voice": {
        "hotkey": "<ctrl>+<alt>+<space>",
        "continuous": False,
        "wake_enabled": False,
        "wake_phrase": "аура",
        "silence_threshold": 0.01,
        "silence_seconds": 1.2,
    },
    "stt": {
        "model": "small",
        "device": "auto",
        "language": "auto",
    },
    "tts": {
        "enabled": True,
        "engine": "edge",
        "voice": "ru-RU-SvetlanaNeural",
        "edge_rate": "+0%",
        "pyttsx3_rate": 185,
    },
    "llm": {
        "provider": "openai",
        "base_url": "",
        "model": "gpt-4o-mini",
        "temperature": 0.2,
    },
    "safety": {
        "computer_control_enabled": True,
        "require_confirmation": True,
    },
    "paths": {
        "workspace": "",
    },
}


def app_dir() -> Path:
    base = os.getenv("APPDATA", str(Path.home()))
    path = Path(base) / "AURA_AI"
    path.mkdir(parents=True, exist_ok=True)
    return path


def _deep_merge(base: dict, override: dict) -> dict:
    result = copy.deepcopy(base)
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(result.get(key), dict):
            result[key] = _deep_merge(result[key], value)
        else:
            result[key] = value
    return result


class Config:
    def __init__(self, data: dict, path: Path):
        self._data = data
        self._path = path

    @classmethod
    def load(cls) -> "Config":
        path = app_dir() / "config.json"
        data = copy.deepcopy(DEFAULT_CONFIG)

        if path.exists():
            try:
                user_data = json.loads(path.read_text(encoding="utf-8"))
                data = _deep_merge(data, user_data)
            except Exception:
                backup = path.with_suffix(".broken.json")
                path.rename(backup)

        cfg = cls(data, path)
        cfg.save()
        return cfg

    def get(self, dotted_key: str, default: Any = None) -> Any:
        node = self._data
        for part in dotted_key.split("."):
            if isinstance(node, dict) and part in node:
                node = node[part]
            else:
                return default
        return node

    def set(self, dotted_key: str, value: Any) -> None:
        parts = dotted_key.split(".")
        node = self._data
        for part in parts[:-1]:
            if part not in node or not isinstance(node[part], dict):
                node[part] = {}
            node = node[part]
        node[parts[-1]] = value

    def save(self) -> None:
        self._path.write_text(
            json.dumps(self._data, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
