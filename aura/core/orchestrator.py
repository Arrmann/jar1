import json
import logging
import threading
import uuid
from datetime import datetime
from typing import Any, Dict, List, Optional

from PySide6.QtCore import QObject, QTimer, Signal

from ..actions import apps, browser, files, system
from ..actions.jarvis_commands import JarvisCommandService
from ..config import Config
from ..db import Database
from ..llm import create_llm
from ..llm.base import LLMResponse
from ..secure_storage import get_secret
from ..stt.recorder import Recorder
from ..stt.whisper_stt import WhisperSTT
from ..tts.speaker import Speaker
from .memory import MemoryManager
from .tool_registry import ToolRegistry


log = logging.getLogger(__name__)


SYSTEM_PROMPT_BASE = """
Ты — JARVIS, персональный голосовой AI-помощник для Windows 10/11.
Отвечай естественно и преимущественно по-русски. Называй себя JARVIS.
Для быстрых системных и прикладных фраз используй run_jarvis_command.
Для свободных сложных задач, рассуждений, поиска, работы с документами и планирования используй подходящие инструменты.
Не утверждай, что действие выполнено, пока инструмент не вернул успешный результат.
Не выполняй выключение, перезагрузку, удаление, очистку корзины и другие рискованные действия без отдельного подтверждения.
Не запускай произвольный код, команды PowerShell или Lua из текста пользователя.
""".strip()


class Orchestrator(QObject):
    message_added = Signal(dict)
    status_changed = Signal(str)
    voice_state_changed = Signal(str)
    confirmation_requested = Signal(dict)
    action_logged = Signal(dict)
    conversations_changed = Signal()
    error = Signal(str)

    request_start_voice = Signal(str)
    request_stop_voice = Signal()

    def __init__(self, cfg: Config):
        super().__init__()

        self.cfg = cfg
        self.db = Database()
        self.memory = MemoryManager(self.db)
        self.llm = create_llm(cfg)
        self.stt = WhisperSTT(cfg)
        self.speaker = Speaker(cfg)
        self.recorder = Recorder(cfg)
        self.jarvis_commands = JarvisCommandService(self.db, self.speaker)

        self.registry = ToolRegistry()
        self._register_tools()

        self.current_conversation = self.db.create_conversation("Новый диалог")
        self.pending_confirms: Dict[str, Dict[str, Any]] = {}
        self.listening_mode = "command"
        self.hotkey_listener = None

        self.autostop_timer = QTimer(self)
        self.autostop_timer.setInterval(100)
        self.autostop_timer.timeout.connect(self._check_autostop)

        self.request_start_voice.connect(self._start_voice_main, type=64)  # Qt.QueuedConnection
        self.request_stop_voice.connect(self._stop_voice_main, type=64)

        self._setup_hotkey()

    # ------------------------- Lifecycle -------------------------

    def start(self) -> None:
        counts = self.jarvis_commands.counts()
        self.status_changed.emit(
            f"JARVIS готов. Команд: {len(self.jarvis_commands.catalog.commands)}; "
            f"доступно сразу: {counts['ready']}. Нажмите микрофон или Ctrl+Alt+Space."
        )
        self.conversations_changed.emit()

    def reload_llm(self) -> None:
        self.llm = create_llm(self.cfg)
        self.status_changed.emit(f"LLM провайдер: {self.llm.name}")

    def reload_stt(self) -> None:
        self.stt.reset()

    def reload_hotkey(self) -> None:
        try:
            if self.hotkey_listener is not None:
                self.hotkey_listener.stop()
        except Exception:
            pass
        self.hotkey_listener = None
        self._setup_hotkey()

    # ------------------------- Hotkey -------------------------

    def _setup_hotkey(self) -> None:
        hotkey = str(self.cfg.get("voice.hotkey", "<ctrl>+<alt>+<space>") or "")
        if not hotkey:
            return

        try:
            from pynput.keyboard import GlobalHotKeys

            self.hotkey_listener = GlobalHotKeys({hotkey: self.toggle_voice})
            self.hotkey_listener.daemon = True
            self.hotkey_listener.start()
            log.info("Global hotkey registered: %s", hotkey)
        except Exception as exc:
            log.error("Hotkey setup failed: %s", exc)

    def toggle_voice(self) -> None:
        if self.recorder.is_active():
            self.request_stop_voice.emit()
        else:
            self.speaker.stop()
            wake_mode = (
                bool(self.cfg.get("voice.continuous", False))
                and bool(self.cfg.get("voice.wake_enabled", False))
            )
            self.request_start_voice.emit("wake" if wake_mode else "command")

    # ------------------------- Conversations -------------------------

    def new_conversation(self, title: str = "Новый диалог") -> int:
        self.current_conversation = self.db.create_conversation(title)
        self.conversations_changed.emit()
        return self.current_conversation

    def set_conversation(self, conversation_id: int) -> None:
        self.current_conversation = conversation_id

    def get_conversations(self) -> List[Dict[str, Any]]:
        return self.db.get_conversations()

    def get_messages(self, conversation_id: int) -> List[Dict[str, Any]]:
        return self.db.get_messages(conversation_id)

    # ------------------------- Tools -------------------------

    def _register_tools(self) -> None:
        def save_memory(args: Dict[str, Any]) -> Dict[str, Any]:
            return self.memory.save(str(args.get("category", "general")), str(args.get("content", "")))

        def search_memory(args: Dict[str, Any]) -> Dict[str, Any]:
            return self.memory.search(str(args.get("query", "")))

        # Memory tools
        self.registry.register(
            "save_memory",
            "Сохранить факт, предпочтение или проект в долговременную память.",
            {
                "type": "object",
                "properties": {
                    "category": {"type": "string", "description": "Категория: preference, project, task, general"},
                    "content": {"type": "string", "description": "Текст памяти"},
                },
                "required": ["content"],
            },
            save_memory,
            dangerous=False,
            category="memory",
        )

        self.registry.register(
            "search_memory",
            "Найти информацию в долговременной памяти по запросу.",
            {
                "type": "object",
                "properties": {
                    "query": {"type": "string", "description": "Поисковый запрос"},
                },
                "required": ["query"],
            },
            search_memory,
            dangerous=False,
            category="memory",
        )

        def run_jarvis_command(args: Dict[str, Any]) -> Dict[str, Any]:
            return self._run_jarvis_command(args)

        self.registry.register(
            "run_jarvis_command",
            "Выполнить одну из команд JARVIS из встроенного каталога. Выбирай точный command_id из контекста команд. Перед рискованными действиями JARVIS запросит подтверждение.",
            {
                "type": "object",
                "properties": {
                    "command_id": {"type": "string", "description": "Точный ID команды из каталога JARVIS"},
                    "utterance": {"type": "string", "description": "Исходная фраза пользователя"},
                    "query": {"type": "string", "description": "Параметр команды: поисковый запрос, время, уровень громкости и т. п."},
                },
                "required": ["command_id"],
            },
            run_jarvis_command,
            dangerous=False,
            category="jarvis",
        )

        # Apps
        self.registry.register(
            "open_app",
            "Открыть или запустить приложение Windows по названию.",
            {
                "type": "object",
                "properties": {
                    "query": {"type": "string", "description": "Название приложения"},
                },
                "required": ["query"],
            },
            apps.open_app,
            dangerous=False,
            category="apps",
        )

        self.registry.register(
            "close_app",
            "Закрыть приложение по имени процесса или названию.",
            {
                "type": "object",
                "properties": {
                    "name": {"type": "string", "description": "Имя приложения или процесса"},
                },
                "required": ["name"],
            },
            apps.close_app,
            dangerous=True,
            category="apps",
        )

        self.registry.register(
            "list_windows",
            "Получить список открытых окон.",
            {"type": "object", "properties": {}},
            apps.list_windows,
            dangerous=False,
            category="apps",
        )

        self.registry.register(
            "switch_window",
            "Переключиться на окно по части заголовка.",
            {
                "type": "object",
                "properties": {
                    "title": {"type": "string", "description": "Заголовок окна"},
                },
                "required": ["title"],
            },
            apps.switch_window,
            dangerous=False,
            category="apps",
        )

        self.registry.register(
            "set_volume",
            "Установить системную громкость в процентах.",
            {
                "type": "object",
                "properties": {
                    "percent": {"type": "integer", "description": "Громкость от 0 до 100"},
                },
                "required": ["percent"],
            },
            apps.set_volume,
            dangerous=False,
            category="system",
        )

        # Files
        self.registry.register(
            "find_files",
            "Искать файлы по имени и/или содержимому.",
            {
                "type": "object",
                "properties": {
                    "query": {"type": "string", "description": "Часть имени файла"},
                    "root": {"type": "string", "description": "Папка или диск, например D:\\"},
                    "content": {"type": "string", "description": "Текст для поиска внутри файлов"},
                    "limit": {"type": "integer", "description": "Максимум результатов"},
                },
            },
            files.find_files,
            dangerous=False,
            category="files",
        )

        self.registry.register(
            "create_folder",
            "Создать папку.",
            {
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Полный путь папки"},
                },
                "required": ["path"],
            },
            files.create_folder,
            dangerous=False,
            category="files",
        )

        self.registry.register(
            "create_document",
            "Создать документ с текстом.",
            {
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Полный путь файла"},
                    "text": {"type": "string", "description": "Содержимое"},
                },
                "required": ["path"],
            },
            files.create_document,
            dangerous=False,
            category="files",
        )

        self.registry.register(
            "read_document",
            "Прочитать содержимое файла или документа.",
            {
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Полный путь файла"},
                },
                "required": ["path"],
            },
            files.read_document,
            dangerous=False,
            category="files",
        )

        self.registry.register(
            "rename_file",
            "Переименовать файл или папку.",
            {
                "type": "object",
                "properties": {
                    "source": {"type": "string"},
                    "destination": {"type": "string"},
                },
                "required": ["source", "destination"],
            },
            files.rename_file,
            dangerous=True,
            category="files",
        )

        self.registry.register(
            "move_file",
            "Переместить файл в другую папку.",
            {
                "type": "object",
                "properties": {
                    "source": {"type": "string"},
                    "destination_folder": {"type": "string"},
                },
                "required": ["source", "destination_folder"],
            },
            files.move_file,
            dangerous=True,
            category="files",
        )

        self.registry.register(
            "delete_file",
            "Удалить файл или папку. Опасное действие.",
            {
                "type": "object",
                "properties": {
                    "path": {"type": "string"},
                },
                "required": ["path"],
            },
            files.delete_file,
            dangerous=True,
            category="files",
        )

        self.registry.register(
            "organize_files",
            "Организовать файлы в папке по расширению или дате.",
            {
                "type": "object",
                "properties": {
                    "folder": {"type": "string"},
                    "mode": {"type": "string", "description": "extension или date"},
                },
                "required": ["folder"],
            },
            files.organize_files,
            dangerous=True,
            category="files",
        )

        # System
        self.registry.register(
            "get_system_info",
            "Получить информацию о системе: CPU, RAM, диски, GPU.",
            {"type": "object", "properties": {}},
            system.get_system_info,
            dangerous=False,
            category="system",
        )

        self.registry.register(
            "get_usage",
            "Получить текущую загрузку системы.",
            {"type": "object", "properties": {}},
            system.get_usage,
            dangerous=False,
            category="system",
        )

        self.registry.register(
            "shutdown_pc",
            "Выключить компьютер. Опасное действие.",
            {"type": "object", "properties": {}},
            system.shutdown,
            dangerous=True,
            category="system",
        )

        self.registry.register(
            "restart_pc",
            "Перезагрузить компьютер. Опасное действие.",
            {"type": "object", "properties": {}},
            system.restart,
            dangerous=True,
            category="system",
        )

        # Browser
        self.registry.register(
            "open_url",
            "Открыть сайт в браузере.",
            {
                "type": "object",
                "properties": {
                    "url": {"type": "string"},
                },
                "required": ["url"],
            },
            browser.open_url,
            dangerous=False,
            category="browser",
        )

        self.registry.register(
            "search_web",
            "Открыть поисковую выдачу в браузере.",
            {
                "type": "object",
                "properties": {
                    "query": {"type": "string"},
                    "engine": {"type": "string", "description": "google, bing, duckduckgo, yandex"},
                },
                "required": ["query"],
            },
            browser.search_web,
            dangerous=False,
            category="browser",
        )

        self.registry.register(
            "youtube_search",
            "Открыть поиск на YouTube.",
            {
                "type": "object",
                "properties": {
                    "query": {"type": "string"},
                },
                "required": ["query"],
            },
            browser.youtube_search,
            dangerous=False,
            category="browser",
        )

        self.registry.register(
            "read_url",
            "Скачать и прочитать текст веб-страницы.",
            {
                "type": "object",
                "properties": {
                    "url": {"type": "string"},
                },
                "required": ["url"],
            },
            browser.read_url,
            dangerous=False,
            category="browser",
        )

    def _run_jarvis_command(self, args: Dict[str, Any]) -> Dict[str, Any]:
        command_id = str(args.get("command_id", "")).strip()
        if not command_id:
            return {"success": False, "message": "Не указан ID команды JARVIS."}

        if self.jarvis_commands.is_dangerous(command_id):
            if bool(self.cfg.get("safety.require_confirmation", True)):
                accepted = self._ask_confirmation(command_id, args)
                if not accepted:
                    return {
                        "success": False,
                        "message": "Действие отменено: подтверждение пользователя не получено.",
                    }

        return self.jarvis_commands.execute(
            command_id,
            utterance=str(args.get("utterance", "")),
            query=str(args.get("query", "")),
        )

    # ------------------------- Confirmation -------------------------

    def resolve_confirmation(self, request_id: str, accepted: bool) -> None:
        item = self.pending_confirms.get(request_id)
        if item:
            item["accepted"] = accepted
            item["event"].set()

    def _ask_confirmation(self, tool_name: str, args: Dict[str, Any]) -> bool:
        request_id = str(uuid.uuid4())
        event = threading.Event()

        self.pending_confirms[request_id] = {
            "event": event,
            "accepted": False,
        }

        self.confirmation_requested.emit(
            {
                "id": request_id,
                "tool": tool_name,
                "args": args,
            }
        )

        event.wait(timeout=180)
        item = self.pending_confirms.pop(request_id, None)
        return bool(item and item.get("accepted"))

    # ------------------------- Execution -------------------------

    def _execute_tool(self, name: str, args: Dict[str, Any]) -> Dict[str, Any]:
        spec = self.registry.get(name)
        if spec is None:
            return {"success": False, "message": f"Инструмент '{name}' не найден."}

        memory_tools = {"save_memory", "search_memory"}

        if spec.name not in memory_tools and not bool(self.cfg.get("safety.computer_control_enabled", True)):
            return {"success": False, "message": "Управление компьютером отключено в настройках."}

        if spec.dangerous and bool(self.cfg.get("safety.require_confirmation", True)):
            accepted = self._ask_confirmation(name, args)
            if not accepted:
                return {"success": False, "message": "Пользователь отклонил выполнение опасного действия."}

        try:
            clean_args = self.registry.validate_args(spec, args)
            result = spec.handler(clean_args)
            status = "success" if result.get("success") else "error"
        except Exception as exc:
            result = {"success": False, "message": str(exc)}
            status = "exception"

        try:
            self.db.log_action(name, args, result, status)
        except Exception:
            pass

        self.action_logged.emit(
            {
                "tool": name,
                "args": args,
                "result": result,
                "status": status,
                "created_at": datetime.utcnow().isoformat(timespec="seconds"),
            }
        )

        return result

    # ------------------------- Chat processing -------------------------

    def submit_text(self, text: str) -> None:
        text = (text or "").strip()
        if not text:
            return

        if not self.current_conversation:
            self.current_conversation = self.db.create_conversation()

        self.db.add_message(self.current_conversation, "user", text)
        self.message_added.emit(
            {
                "conversation_id": self.current_conversation,
                "role": "user",
                "content": text,
            }
        )

        threading.Thread(target=self._process_user_text, args=(text,), daemon=True).start()

    def _system_prompt(self, user_text: str) -> str:
        relevant = self.memory.relevant_context(user_text)
        now = datetime.now().strftime("%Y-%m-%d %H:%M")

        prompt = SYSTEM_PROMPT_BASE + f"\nТекущее время: {now}."

        command_context = self.jarvis_commands.llm_context(limit=70)
        if command_context:
            prompt += "\n\n" + command_context

        if relevant:
            prompt += "\n\n" + relevant

        return prompt

    def _build_messages(self, user_text: str) -> List[Dict[str, Any]]:
        messages = [{"role": "system", "content": self._system_prompt(user_text)}]

        history = self.db.get_messages(self.current_conversation, limit=16)
        for msg in history:
            messages.append({"role": msg["role"], "content": msg["content"]})

        return messages

    def _process_user_text(self, user_text: str) -> None:
        try:
            self.voice_state_changed.emit("thinking")
            self.status_changed.emit("JARVIS анализирует запрос...")

            # Exact command aliases are handled locally first. This keeps
            # volume, browser, timer and Windows shortcuts available offline.
            matched = self.jarvis_commands.match(user_text)
            if matched:
                command_id = matched["command_id"]
                self.status_changed.emit(f"Выполняю команду: {command_id}")
                result = self._execute_tool(
                    "run_jarvis_command",
                    {
                        "command_id": command_id,
                        "utterance": matched.get("utterance", user_text),
                        "query": matched.get("query", ""),
                    },
                )
                final_content = str(result.get("message") or ("Готово." if result.get("success") else "Команда не выполнена."))
                self.db.add_message(self.current_conversation, "assistant", final_content)
                self.message_added.emit({
                    "conversation_id": self.current_conversation,
                    "role": "assistant",
                    "content": final_content,
                })
                self.voice_state_changed.emit("speaking")
                self.status_changed.emit("JARVIS отвечает...")
                self.speaker.speak(final_content)
                if not self.speaker.interrupted:
                    self._maybe_continue_listening_after_response()
                else:
                    self.voice_state_changed.emit("idle")
                return

            tools = self.registry.schemas() if bool(self.cfg.get("safety.computer_control_enabled", True)) else None
            messages = self._build_messages(user_text)
            final_content = ""

            for _ in range(4):
                response: LLMResponse = self.llm.chat(messages, tools=tools, tool_choice="auto")

                if not response.tool_calls:
                    final_content = response.content or "Готово."
                    break

                assistant_message: Dict[str, Any] = {
                    "role": "assistant",
                    "content": response.content or "",
                    "tool_calls": [
                        {
                            "id": tc.id,
                            "type": "function",
                            "function": {
                                "name": tc.name,
                                "arguments": json.dumps(tc.arguments, ensure_ascii=False),
                            },
                        }
                        for tc in response.tool_calls
                    ],
                }
                messages.append(assistant_message)

                for tc in response.tool_calls:
                    self.status_changed.emit(f"Выполняю: {tc.name}")
                    result = self._execute_tool(tc.name, tc.arguments)

                    messages.append(
                        {
                            "role": "tool",
                            "tool_call_id": tc.id,
                            "name": tc.name,
                            "content": json.dumps(result, ensure_ascii=False, default=str),
                        }
                    )

            if not final_content:
                final_content = "Действия выполнены."

            self.db.add_message(self.current_conversation, "assistant", final_content)
            self.message_added.emit(
                {
                    "conversation_id": self.current_conversation,
                    "role": "assistant",
                    "content": final_content,
                }
            )

            self.voice_state_changed.emit("speaking")
            self.status_changed.emit("JARVIS отвечает...")
            self.speaker.speak(final_content)

            if not self.speaker.interrupted:
                self._maybe_continue_listening_after_response()
            else:
                self.voice_state_changed.emit("idle")

        except Exception as exc:
            log.exception("Chat processing failed")
            self.error.emit(str(exc))
            self.message_added.emit(
                {
                    "conversation_id": self.current_conversation,
                    "role": "assistant",
                    "content": f"Ошибка: {exc}",
                }
            )
            self.voice_state_changed.emit("idle")

    # ------------------------- Voice -------------------------

    def _start_voice_main(self, mode: str) -> None:
        self.speaker.stop()
        self.listening_mode = mode

        auto_stop = bool(self.cfg.get("voice.continuous", False)) or mode == "wake"

        try:
            self.recorder.start(auto_stop=auto_stop)
            self.autostop_timer.start()

            if mode == "wake":
                self.voice_state_changed.emit("listening")
                self.status_changed.emit("Ожидаю фразу активации...")
            else:
                self.voice_state_changed.emit("listening")
                self.status_changed.emit("Слушаю...")
        except Exception as exc:
            self.error.emit(f"Микрофон недоступен: {exc}")
            self.voice_state_changed.emit("idle")

    def _stop_voice_main(self) -> None:
        self.autostop_timer.stop()

        if not self.recorder.is_active():
            self.voice_state_changed.emit("idle")
            return

        audio = self.recorder.stop()

        if len(audio) < 1600:
            self.voice_state_changed.emit("idle")
            self.status_changed.emit("Речь не обнаружена.")
            self._maybe_continue_listening_after_silence()
            return

        self.voice_state_changed.emit("thinking")
        self.status_changed.emit("Распознаю речь...")

        threading.Thread(target=self._transcribe_thread, args=(audio, self.listening_mode), daemon=True).start()

    def _check_autostop(self) -> None:
        if self.recorder.active and self.recorder.autostop_triggered:
            self.recorder.autostop_triggered = False
            self.request_stop_voice.emit()

    def _transcribe_thread(self, audio, mode: str) -> None:
        try:
            text = self.stt.transcribe(audio)

            if not text:
                self.status_changed.emit("Не удалось распознать речь.")
                self.voice_state_changed.emit("idle")
                self._maybe_continue_listening_after_silence()
                return

            if mode == "wake":
                wake_phrase = str(self.cfg.get("voice.wake_phrase", "джарвис") or "").strip().lower()
                if wake_phrase and wake_phrase in text.lower():
                    self.status_changed.emit("Активация по фразе.")
                    self.request_start_voice.emit("command")
                else:
                    self._maybe_continue_listening_after_silence()
            else:
                self.submit_text(text)

        except Exception as exc:
            log.exception("STT failed")
            self.error.emit(str(exc))
            self.voice_state_changed.emit("idle")

    def _maybe_continue_listening_after_response(self) -> None:
        if bool(self.cfg.get("voice.continuous", False)):
            mode = "wake" if bool(self.cfg.get("voice.wake_enabled", False)) else "command"
            self.request_start_voice.emit(mode)
        else:
            self.voice_state_changed.emit("idle")
            self.status_changed.emit("Готов.")

    def _maybe_continue_listening_after_silence(self) -> None:
        if bool(self.cfg.get("voice.continuous", False)):
            mode = "wake" if bool(self.cfg.get("voice.wake_enabled", False)) else "command"
            self.request_start_voice.emit(mode)
        else:
            self.voice_state_changed.emit("idle")
