import json
import uuid
from typing import Any, Dict, List

import requests

from .base import BaseLLM, LLMError, LLMResponse, ToolCall


DEFAULT_BASE_URLS = {
    "openai": "https://api.openai.com/v1",
    "groq": "https://api.groq.com/openai/v1",
}


class OpenAICompatibleLLM(BaseLLM):
    def __init__(
        self,
        provider: str,
        api_key: str,
        model: str,
        base_url: str = "",
        temperature: float = 0.2,
    ):
        self.provider = provider.lower()
        self.name = f"openai-compatible:{self.provider}"
        self.api_key = api_key
        self.model = model
        self.base_url = (base_url or DEFAULT_BASE_URLS.get(self.provider, DEFAULT_BASE_URLS["openai"])).rstrip("/")
        self.temperature = temperature

        if not self.api_key:
            raise LLMError(f"No API key for provider {self.provider}")

    def chat(
        self,
        messages: List[Dict[str, Any]],
        tools: List[Dict[str, Any]] | None = None,
        tool_choice: str = "auto",
    ) -> LLMResponse:
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
        }

        payload: Dict[str, Any] = {
            "model": self.model,
            "messages": messages,
            "temperature": self.temperature,
        }

        if tools:
            payload["tools"] = [{"type": "function", "function": tool} for tool in tools]
            payload["tool_choice"] = tool_choice

        try:
            resp = requests.post(
                f"{self.base_url}/chat/completions",
                headers=headers,
                json=payload,
                timeout=180,
            )
        except requests.RequestException as exc:
            raise LLMError(f"Сетевая ошибка LLM: {exc}") from exc

        if resp.status_code != 200:
            raise LLMError(f"LLM HTTP {resp.status_code}: {resp.text[:500]}")

        data = resp.json()

        try:
            message = data["choices"][0]["message"]
        except Exception as exc:
            raise LLMError(f"Некорректный ответ LLM: {data}") from exc

        tool_calls: List[ToolCall] = []

        for tc in message.get("tool_calls") or []:
            fn = tc.get("function", {})
            raw_args = fn.get("arguments", "{}")
            try:
                args = json.loads(raw_args) if isinstance(raw_args, str) else raw_args
            except json.JSONDecodeError:
                args = {"raw": raw_args}

            tool_calls.append(
                ToolCall(
                    id=tc.get("id") or str(uuid.uuid4()),
                    name=fn.get("name", ""),
                    arguments=args or {},
                )
            )

        return LLMResponse(content=message.get("content") or "", tool_calls=tool_calls)
