import json
import uuid
from typing import Any, Dict, List

import requests

from .base import BaseLLM, LLMError, LLMResponse, ToolCall


class OllamaLLM(BaseLLM):
    def __init__(self, model: str, base_url: str = "http://localhost:11434", temperature: float = 0.2):
        self.name = "ollama"
        self.model = model or "llama3.1"
        self.base_url = (base_url or "http://localhost:11434").rstrip("/")
        self.temperature = temperature

    def chat(
        self,
        messages: List[Dict[str, Any]],
        tools: List[Dict[str, Any]] | None = None,
        tool_choice: str = "auto",
    ) -> LLMResponse:
        payload: Dict[str, Any] = {
            "model": self.model,
            "messages": messages,
            "stream": False,
            "options": {"temperature": self.temperature},
        }

        if tools:
            payload["tools"] = tools

        try:
            resp = requests.post(f"{self.base_url}/api/chat", json=payload, timeout=300)
        except requests.RequestException as exc:
            raise LLMError(f"Ollama недоступна: {exc}") from exc

        if resp.status_code != 200:
            raise LLMError(f"Ollama HTTP {resp.status_code}: {resp.text[:500]}")

        data = resp.json()
        message = data.get("message", {})

        tool_calls: List[ToolCall] = []

        for tc in message.get("tool_calls") or []:
            fn = tc.get("function", {})
            args = fn.get("arguments", {})
            if isinstance(args, str):
                try:
                    args = json.loads(args)
                except json.JSONDecodeError:
                    args = {"raw": args}

            tool_calls.append(
                ToolCall(
                    id=str(uuid.uuid4()),
                    name=fn.get("name", ""),
                    arguments=args or {},
                )
            )

        return LLMResponse(content=message.get("content") or "", tool_calls=tool_calls)
