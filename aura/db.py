import json
import sqlite3
import threading
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional

from .config import app_dir


def utcnow() -> str:
    return datetime.utcnow().isoformat(timespec="seconds")


class Database:
    def __init__(self, path: Optional[Path] = None):
        self.path = path or (app_dir() / "aura.db")
        self.lock = threading.RLock()
        self.conn = sqlite3.connect(str(self.path), check_same_thread=False)
        self.conn.row_factory = sqlite3.Row
        self._init()

    def _init(self) -> None:
        with self.lock:
            cur = self.conn.cursor()
            cur.executescript(
                """
                CREATE TABLE IF NOT EXISTS conversations(
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    title TEXT NOT NULL,
                    created_at TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS messages(
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    conversation_id INTEGER NOT NULL,
                    role TEXT NOT NULL,
                    content TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    FOREIGN KEY(conversation_id) REFERENCES conversations(id)
                );

                CREATE TABLE IF NOT EXISTS memories(
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    category TEXT NOT NULL DEFAULT 'general',
                    content TEXT NOT NULL,
                    created_at TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS actions_log(
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    tool TEXT NOT NULL,
                    args TEXT NOT NULL,
                    result TEXT NOT NULL,
                    status TEXT NOT NULL,
                    created_at TEXT NOT NULL
                );
                """
            )
            self.conn.commit()

    # Conversations

    def create_conversation(self, title: str = "Новый диалог") -> int:
        with self.lock:
            cur = self.conn.cursor()
            cur.execute(
                "INSERT INTO conversations(title, created_at) VALUES (?, ?)",
                (title, utcnow()),
            )
            self.conn.commit()
            return int(cur.lastrowid)

    def get_conversations(self) -> List[Dict[str, Any]]:
        with self.lock:
            cur = self.conn.cursor()
            cur.execute("SELECT id, title, created_at FROM conversations ORDER BY id DESC")
            return [dict(row) for row in cur.fetchall()]

    def rename_conversation(self, conversation_id: int, title: str) -> None:
        with self.lock:
            cur = self.conn.cursor()
            cur.execute(
                "UPDATE conversations SET title=? WHERE id=?",
                (title, conversation_id),
            )
            self.conn.commit()

    # Messages

    def add_message(self, conversation_id: int, role: str, content: str) -> int:
        with self.lock:
            cur = self.conn.cursor()
            cur.execute(
                "INSERT INTO messages(conversation_id, role, content, created_at) VALUES (?, ?, ?, ?)",
                (conversation_id, role, content, utcnow()),
            )
            self.conn.commit()
            return int(cur.lastrowid)

    def get_messages(self, conversation_id: int, limit: int = 0) -> List[Dict[str, Any]]:
        with self.lock:
            cur = self.conn.cursor()
            if limit > 0:
                cur.execute(
                    """
                    SELECT role, content, created_at FROM (
                        SELECT role, content, created_at, id
                        FROM messages
                        WHERE conversation_id=?
                        ORDER BY id DESC
                        LIMIT ?
                    ) ORDER BY id ASC
                    """,
                    (conversation_id, limit),
                )
            else:
                cur.execute(
                    "SELECT role, content, created_at FROM messages WHERE conversation_id=? ORDER BY id ASC",
                    (conversation_id,),
                )
            return [dict(row) for row in cur.fetchall()]

    def search_messages(self, query: str, limit: int = 10) -> List[Dict[str, Any]]:
        q = f"%{query.strip()}%"
        with self.lock:
            cur = self.conn.cursor()
            cur.execute(
                """
                SELECT conversation_id, role, content, created_at
                FROM messages
                WHERE content LIKE ?
                ORDER BY id DESC
                LIMIT ?
                """,
                (q, limit),
            )
            return [dict(row) for row in cur.fetchall()]

    # Memories

    def add_memory(self, category: str, content: str) -> int:
        with self.lock:
            cur = self.conn.cursor()
            cur.execute(
                "INSERT INTO memories(category, content, created_at) VALUES (?, ?, ?)",
                (category, content, utcnow()),
            )
            self.conn.commit()
            return int(cur.lastrowid)

    def get_memories(self) -> List[Dict[str, Any]]:
        with self.lock:
            cur = self.conn.cursor()
            cur.execute("SELECT id, category, content, created_at FROM memories ORDER BY id DESC")
            return [dict(row) for row in cur.fetchall()]

    def delete_memory(self, memory_id: int) -> None:
        with self.lock:
            cur = self.conn.cursor()
            cur.execute("DELETE FROM memories WHERE id=?", (memory_id,))
            self.conn.commit()

    def update_memory(self, memory_id: int, category: str, content: str) -> None:
        with self.lock:
            cur = self.conn.cursor()
            cur.execute(
                "UPDATE memories SET category=?, content=? WHERE id=?",
                (category, content, memory_id),
            )
            self.conn.commit()

    def search_memories(self, query: str, limit: int = 5) -> List[Dict[str, Any]]:
        q = f"%{query.strip()}%"
        with self.lock:
            cur = self.conn.cursor()
            cur.execute(
                """
                SELECT id, category, content, created_at
                FROM memories
                WHERE content LIKE ? OR category LIKE ?
                ORDER BY id DESC
                LIMIT ?
                """,
                (q, q, limit),
            )
            return [dict(row) for row in cur.fetchall()]

    # Actions

    def log_action(self, tool: str, args: Dict[str, Any], result: Dict[str, Any], status: str) -> int:
        with self.lock:
            cur = self.conn.cursor()
            cur.execute(
                "INSERT INTO actions_log(tool, args, result, status, created_at) VALUES (?, ?, ?, ?, ?)",
                (
                    tool,
                    json.dumps(args, ensure_ascii=False, default=str),
                    json.dumps(result, ensure_ascii=False, default=str),
                    status,
                    utcnow(),
                ),
            )
            self.conn.commit()
            return int(cur.lastrowid)

    def get_actions(self, limit: int = 200) -> List[Dict[str, Any]]:
        with self.lock:
            cur = self.conn.cursor()
            cur.execute(
                "SELECT tool, args, result, status, created_at FROM actions_log ORDER BY id DESC LIMIT ?",
                (limit,),
            )
            rows = []
            for row in cur.fetchall():
                item = dict(row)
                try:
                    item["args"] = json.loads(item["args"])
                except Exception:
                    pass
                try:
                    item["result"] = json.loads(item["result"])
                except Exception:
                    pass
                rows.append(item)
            return rows
