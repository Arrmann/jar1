from __future__ import annotations

import json
import re
import uuid
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit

from ..config import app_dir
from .command_catalog import normalize_phrase


MAX_COMMANDS = 200
MAX_STEPS = 30
ALLOWED_STEP_TYPES = {"command", "speak", "wait", "open_url"}


class CustomCommandError(ValueError):
    pass


class CustomCommandStore:
    """User-defined safe command sequences, stored separately from app code."""

    def __init__(self, path: Path | None = None):
        self.path = path or (app_dir() / "custom_commands.json")
        self.commands: list[dict[str, Any]] = []
        self.load()

    def load(self) -> None:
        try:
            raw = json.loads(self.path.read_text(encoding="utf-8"))
        except FileNotFoundError:
            self.commands = []
            return
        except (OSError, json.JSONDecodeError) as exc:
            raise CustomCommandError(f"Не удалось прочитать пользовательские команды: {exc}") from exc

        rows = raw.get("commands", []) if isinstance(raw, dict) else raw
        if not isinstance(rows, list):
            raise CustomCommandError("Файл пользовательских команд имеет неверный формат.")
        self.commands = [self.validate(row) for row in rows if isinstance(row, dict)]

    @staticmethod
    def validate(command: dict[str, Any]) -> dict[str, Any]:
        name = str(command.get("name", "")).strip()
        if not name or len(name) > 80:
            raise CustomCommandError("Название команды должно содержать от 1 до 80 символов.")

        raw_phrases = command.get("phrases_ru") or []
        if isinstance(raw_phrases, str):
            raw_phrases = re.split(r"[,;\n]", raw_phrases)
        phrases = []
        seen = set()
        for item in raw_phrases:
            phrase = re.sub(r"\s+", " ", str(item or "")).strip()
            key = normalize_phrase(phrase)
            if not key or key in seen:
                continue
            if len(key) < 2 or len(key) > 100:
                raise CustomCommandError("Фразы активации должны содержать от 2 до 100 символов.")
            phrases.append(phrase)
            seen.add(key)
        if not phrases or len(phrases) > 12:
            raise CustomCommandError("Добавьте от 1 до 12 уникальных фраз активации.")

        steps = command.get("steps") or []
        if not isinstance(steps, list) or not steps or len(steps) > MAX_STEPS:
            raise CustomCommandError(f"Сценарий должен содержать от 1 до {MAX_STEPS} шагов.")

        clean_steps = []
        for index, raw in enumerate(steps, start=1):
            if not isinstance(raw, dict):
                raise CustomCommandError(f"Шаг {index}: неверный формат.")
            kind = str(raw.get("type", "")).strip().lower()
            if kind not in ALLOWED_STEP_TYPES:
                raise CustomCommandError(f"Шаг {index}: тип действия не поддерживается.")
            step: dict[str, Any] = {"type": kind}

            if kind == "command":
                command_id = str(raw.get("command_id", "")).strip()
                if not re.fullmatch(r"[a-zA-Z0-9_]{2,80}", command_id):
                    raise CustomCommandError(f"Шаг {index}: неверный ID системной команды.")
                step["command_id"] = command_id
                step["query"] = str(raw.get("query", ""))[:300]

            elif kind == "speak":
                text = str(raw.get("text", "")).strip()
                if not text or len(text) > 500:
                    raise CustomCommandError(f"Шаг {index}: ответ должен содержать от 1 до 500 символов.")
                step["text"] = text

            elif kind == "wait":
                try:
                    seconds = float(raw.get("seconds", 1))
                except (TypeError, ValueError) as exc:
                    raise CustomCommandError(f"Шаг {index}: укажите длительность паузы.") from exc
                if not 0 <= seconds <= 30:
                    raise CustomCommandError(f"Шаг {index}: пауза может составлять от 0 до 30 секунд.")
                step["seconds"] = seconds

            elif kind == "open_url":
                url = str(raw.get("url", "")).strip()
                parsed = urlsplit(url)
                if parsed.scheme not in {"http", "https"} or not parsed.netloc:
                    raise CustomCommandError(f"Шаг {index}: разрешены только полные HTTP/HTTPS-ссылки.")
                if len(url) > 2048:
                    raise CustomCommandError(f"Шаг {index}: ссылка слишком длинная.")
                step["url"] = url

            clean_steps.append(step)

        return {
            "id": str(command.get("id") or uuid.uuid4().hex),
            "name": name,
            "phrases_ru": phrases,
            "enabled": bool(command.get("enabled", True)),
            "steps": clean_steps,
        }

    def save(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        payload = {"schema_version": 1, "commands": self.commands}
        temp = self.path.with_suffix(self.path.suffix + ".tmp")
        temp.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
        temp.replace(self.path)

    @staticmethod
    def _validate_trigger_collisions(commands: list[dict[str, Any]]) -> None:
        seen: list[tuple[str, str]] = []
        for command in commands:
            for phrase in command.get("phrases_ru", []):
                key = normalize_phrase(phrase)
                for other_key, other_name in seen:
                    if key == other_key or key.startswith(other_key + " ") or other_key.startswith(key + " "):
                        raise CustomCommandError(
                            f"Фраза «{phrase}» конфликтует с фразой сценария «{other_name}». "
                            "Используйте более уникальный триггер."
                        )
                seen.append((key, str(command.get("name", "сценарий"))))

    def upsert(self, command: dict[str, Any]) -> dict[str, Any]:
        clean = self.validate(command)
        candidate = [row for row in self.commands if row["id"] != clean["id"]] + [clean]
        self._validate_trigger_collisions(candidate)
        existing = next((i for i, row in enumerate(self.commands) if row["id"] == clean["id"]), None)
        if existing is None:
            if len(self.commands) >= MAX_COMMANDS:
                raise CustomCommandError(f"Можно сохранить не более {MAX_COMMANDS} пользовательских команд.")
            self.commands.append(clean)
        else:
            self.commands[existing] = clean
        self.save()
        return clean

    def delete(self, command_id: str) -> bool:
        before = len(self.commands)
        self.commands = [row for row in self.commands if row["id"] != str(command_id)]
        if len(self.commands) != before:
            self.save()
            return True
        return False

    def get(self, command_id: str) -> dict[str, Any] | None:
        return next((row for row in self.commands if row["id"] == str(command_id)), None)

    def match(self, utterance: str) -> dict[str, Any] | None:
        original = str(utterance or "").strip()
        text = normalize_phrase(original)
        for prefix in ("джарвис", "джервис", "jarvis", "hey jarvis"):
            if text == prefix:
                return None
            if text.startswith(prefix + " "):
                text = text[len(prefix):].strip()
                break

        candidates = []
        for command in self.commands:
            if not command.get("enabled", True):
                continue
            for phrase in command.get("phrases_ru", []):
                key = normalize_phrase(phrase)
                if text == key:
                    candidates.append((len(key), command, ""))
                elif text.startswith(key + " "):
                    candidates.append((len(key), command, text[len(key):].strip()))
        if not candidates:
            return None
        candidates.sort(key=lambda item: item[0], reverse=True)
        best_length = candidates[0][0]
        winners = [row for row in candidates if row[0] == best_length]
        if len({row[1]["id"] for row in winners}) != 1:
            return None
        _, command, query = winners[0]
        return {"command": command, "query": query, "utterance": original}

    def export_data(self) -> dict[str, Any]:
        return {"schema_version": 1, "commands": self.commands}

    def import_data(self, payload: dict[str, Any]) -> int:
        rows = payload.get("commands", []) if isinstance(payload, dict) else []
        if not isinstance(rows, list):
            raise CustomCommandError("В файле импорта не найден список команд.")
        validated = [self.validate(row) for row in rows if isinstance(row, dict)]
        by_id = {row["id"]: row for row in self.commands}
        for row in validated:
            by_id[row["id"]] = row
        if len(by_id) > MAX_COMMANDS:
            raise CustomCommandError(f"После импорта будет больше {MAX_COMMANDS} команд.")
        merged = list(by_id.values())
        self._validate_trigger_collisions(merged)
        self.commands = merged
        self.save()
        return len(validated)
