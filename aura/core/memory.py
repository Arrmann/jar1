from typing import Any, Dict, List

from ..db import Database


class MemoryManager:
    def __init__(self, db: Database):
        self.db = db

    def save(self, category: str, content: str) -> Dict[str, Any]:
        category = (category or "general").strip() or "general"
        content = (content or "").strip()
        if not content:
            return {"success": False, "message": "Пустая память."}
        memory_id = self.db.add_memory(category, content)
        return {"success": True, "id": memory_id, "message": "Сохранено в памяти."}

    def search(self, query: str) -> Dict[str, Any]:
        query = (query or "").strip()
        if not query:
            return {"success": False, "message": "Пустой запрос."}
        results = self.db.search_memories(query, limit=10)
        return {"success": True, "results": results}

    def relevant_context(self, query: str) -> str:
        query = (query or "").strip()
        if not query:
            return ""

        parts: List[str] = []

        memories = self.db.search_memories(query, limit=5)
        if memories:
            parts.append("Релевантная долговременная память:")
            for mem in memories:
                parts.append(f"- [{mem['category']}] {mem['content']}")

        messages = self.db.search_messages(query, limit=5)
        if messages:
            parts.append("Похожие фрагменты прошлых диалогов:")
            for msg in messages:
                content = msg["content"].replace("\n", " ")
                if len(content) > 300:
                    content = content[:300] + "..."
                parts.append(f"- {msg['role']}: {content}")

        return "\n".join(parts)
