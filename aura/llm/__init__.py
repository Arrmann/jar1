"""LLM provider factory for JARVIS."""

from .base import LLMError
from .offline import OfflineLLM
from .ollama_provider import OllamaLLM
from .openai_provider import OpenAICompatibleLLM
from ..secure_storage import get_secret


def create_llm(cfg):
    """Create the configured provider; fall back safely to offline mode."""
    provider = str(cfg.get("llm.provider", "offline") or "offline").strip().lower()
    model = str(cfg.get("llm.model", "") or "").strip()
    base_url = str(cfg.get("llm.base_url", "") or "").strip()
    temperature = float(cfg.get("llm.temperature", 0.2) or 0.0)

    if provider == "offline":
        return OfflineLLM()

    if provider == "ollama":
        return OllamaLLM(
            model=model or "llama3.1",
            base_url=base_url or "http://localhost:11434",
            temperature=temperature,
        )

    if provider in ("openai", "groq"):
        api_key = get_secret(f"{provider}_api_key")
        if not api_key:
            return OfflineLLM(f"Не задан API-ключ провайдера {provider}.")
        return OpenAICompatibleLLM(
            provider=provider,
            api_key=api_key,
            model=model or ("gpt-4o-mini" if provider == "openai" else "llama-3.3-70b-versatile"),
            base_url=base_url,
            temperature=temperature,
        )

    return OfflineLLM(f"Неизвестный LLM-провайдер: {provider}.")
