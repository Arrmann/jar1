from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any


def normalize_phrase(value: str) -> str:
    value = str(value or "").casefold().replace("ё", "е")
    value = re.sub(r"[^\w\s:+-]", " ", value, flags=re.UNICODE)
    return re.sub(r"\s+", " ", value).strip()


class CommandCatalog:
    """Loads the JARVIS demo command metadata without executing imported Lua scripts."""

    def __init__(self, path: Path | None = None):
        project_root = Path(__file__).resolve().parents[2]
        self.path = path or (project_root / "integration" / "command-catalog.json")
        self.data: dict[str, Any] = {}
        self.commands: list[dict[str, Any]] = []
        self.by_id: dict[str, dict[str, Any]] = {}
        self.load()

    def load(self) -> None:
        if not self.path.is_file():
            self.data = {"total_commands": 0, "categories": {}, "commands": []}
            self.commands = []
            self.by_id = {}
            return
        try:
            data = json.loads(self.path.read_text(encoding="utf-8"))
            commands = data.get("commands", [])
            if not isinstance(commands, list):
                raise ValueError("Поле commands должно быть списком")
            clean = []
            for item in commands:
                if not isinstance(item, dict) or not item.get("id"):
                    continue
                clean.append(item)
            self.data = data
            self.commands = clean
            self.by_id = {str(item["id"]): item for item in clean}
        except (OSError, json.JSONDecodeError, ValueError) as exc:
            raise RuntimeError(f"Не удалось загрузить каталог команд: {exc}") from exc

    def get(self, command_id: str) -> dict[str, Any] | None:
        return self.by_id.get(str(command_id))

    def search(self, query: str = "", group: str = "") -> list[dict[str, Any]]:
        needle = normalize_phrase(query)
        group = str(group or "").casefold()
        rows = []
        for item in self.commands:
            if group and str(item.get("group", "")).casefold() != group:
                continue
            haystack = " ".join(
                [str(item.get("id", "")), str(item.get("description", ""))]
                + list(item.get("phrases_ru") or [])
                + list(item.get("phrases_en") or [])
            )
            if not needle or needle in normalize_phrase(haystack):
                rows.append(item)
        return rows

    def match(
        self,
        utterance: str,
        enabled_ids: set[str] | frozenset[str] | None = None,
        wake_phrase: str = "джарвис",
    ) -> dict[str, Any] | None:
        original = str(utterance or "").strip()
        text = normalize_phrase(original)
        wake = normalize_phrase(wake_phrase)
        for prefix in ("джарвис", "джервис", "jarvis", "hey jarvis"):
            if text == prefix:
                return None
            if text.startswith(prefix + " "):
                text = text[len(prefix):].strip()
                break
        if wake and text.startswith(wake + " "):
            text = text[len(wake):].strip()

        candidates: list[tuple[int, dict[str, Any], str]] = []
        for item in self.commands:
            command_id = str(item.get("id", ""))
            if enabled_ids is not None and command_id not in enabled_ids:
                continue
            phrases = list(item.get("phrases_ru") or []) + list(item.get("phrases_en") or [])
            for raw_phrase in phrases:
                phrase = normalize_phrase(raw_phrase)
                if len(phrase) < 2:
                    continue
                if text == phrase:
                    candidates.append((len(phrase), item, ""))
                elif text.startswith(phrase + " "):
                    tail = text[len(phrase):].strip()
                    candidates.append((len(phrase), item, tail))
        if not candidates:
            return None
        candidates.sort(key=lambda row: row[0], reverse=True)
        best_len, best, tail = candidates[0]
        # If two commands use the same longest phrase, leave the decision to the LLM.
        ties = [row for row in candidates if row[0] == best_len and row[1].get("id") != best.get("id")]
        if ties:
            return None
        return {"command": best, "command_id": str(best["id"]), "query": tail, "utterance": original}
