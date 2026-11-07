import uuid
from typing import Any, Dict, List

from .base import BaseLLM, LLMResponse, ToolCall


VERBS_OPEN = ["открой", "запусти", "открыть", "запустить", "включи"]
VERBS_CLOSE = ["закрой", "закрыть", "останови", "выключи приложение"]
SYSTEM_WORDS = ["память", "загрузка", "процессор", "диск", "система", "gpu", "видеокарта"]


def _extract_after(text: str, words: List[str]) -> str:
    lower = text.lower()
    for word in words:
        if word in lower:
            index = lower.rfind(word) + len(word)
            return text[index:].strip(" .,!?:;«»\"'")
    return text.strip()


class OfflineLLM(BaseLLM):
    """
    Резервный локальный движок без внешнего API.
    Он не является полноценной LLM, но позволяет приложению оставаться рабочим
    и выполнять базовые команды, если облачный провайдер не настроен.
    """

    def __init__(self, reason: str = ""):
        self.name = "offline"
        self.reason = reason

    def chat(
        self,
        messages: List[Dict[str, Any]],
        tools: List[Dict[str, Any]] | None = None,
        tool_choice: str = "auto",
    ) -> LLMResponse:
        user_text = ""
        for msg in reversed(messages):
            if msg.get("role") == "user":
                user_text = str(msg.get("content", ""))
                break

        text = user_text.strip()
        lower = text.lower()

        if tools:
            calls: List[ToolCall] = []

            if any(w in lower for w in ["http://", "https://", "www."]):
                url = text.split()[-1]
                if not url.startswith("http"):
                    url = "https://" + url
                calls.append(ToolCall(str(uuid.uuid4()), "open_url", {"url": url}))

            elif any(w in lower for w in ["найди в интернете", "погугли", "поищи в интернете", "search web"]):
                calls.append(ToolCall(str(uuid.uuid4()), "search_web", {"query": text}))

            elif any(w in lower for w in ["найди файл", "поиск файла", "найди документ", "файл по имени"]):
                calls.append(ToolCall(str(uuid.uuid4()), "find_files", {"query": _extract_after(text, ["найди файл", "найди документ", "файл"]) }))

            elif any(w in lower for w in SYSTEM_WORDS):
                calls.append(ToolCall(str(uuid.uuid4()), "get_system_info", {}))

            elif any(w in lower for w in VERBS_CLOSE):
                calls.append(ToolCall(str(uuid.uuid4()), "close_app", {"name": _extract_after(text, VERBS_CLOSE)}))

            elif any(w in lower for w in VERBS_OPEN):
                calls.append(ToolCall(str(uuid.uuid4()), "open_app", {"query": _extract_after(text, VERBS_OPEN)}))

            if calls:
                return LLMResponse(content="", tool_calls=calls)

        reason = f" Причина: {self.reason}" if self.reason else ""
        return LLMResponse(
            content=(
                "Я работаю в офлайн-режиме без подключённой LLM."
                f"{reason} Настройте OpenAI/Groq/Ollama в разделе настроек. "
                "Без LLM я могу выполнять только простые локальные команды: "
                "открой приложение, закрой приложение, найди файл, покажи информацию о системе."
            )
        )
