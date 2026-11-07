import json

from PySide6.QtCore import Qt
from PySide6.QtWidgets import (
    QCheckBox,
    QComboBox,
    QDoubleSpinBox,
    QFormLayout,
    QFrame,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QListWidget,
    QListWidgetItem,
    QMessageBox,
    QPushButton,
    QSplitter,
    QTableWidget,
    QTableWidgetItem,
    QTextBrowser,
    QVBoxLayout,
    QWidget,
)

from ..secure_storage import get_secret, set_secret
from .visualizer import AuraVisualizer


def html_escape(text: str) -> str:
    return (
        str(text)
        .replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace("\n", "<br>")
    )


class ChatWidget(QWidget):
    def __init__(self, orchestrator):
        super().__init__()
        self.orch = orchestrator

        root = QHBoxLayout(self)
        root.setContentsMargins(14, 14, 14, 14)

        splitter = QSplitter(Qt.Orientation.Horizontal)

        # Left: conversations
        left = QWidget()
        left_layout = QVBoxLayout(left)
        left_layout.setContentsMargins(0, 0, 0, 0)

        self.new_chat_btn = QPushButton("Новый чат")
        self.conv_list = QListWidget()
        left_layout.addWidget(self.new_chat_btn)
        left_layout.addWidget(self.conv_list)

        # Right: chat
        right = QWidget()
        right_layout = QVBoxLayout(right)
        right_layout.setContentsMargins(0, 0, 0, 0)

        card = QFrame()
        card.setObjectName("Card")
        card_layout = QVBoxLayout(card)

        self.visual = AuraVisualizer()
        self.status_label = QLabel("AURA готов")
        self.status_label.setObjectName("SubtitleLabel")
        self.status_label.setAlignment(Qt.AlignmentFlag.AlignHCenter)

        self.messages = QTextBrowser()
        self.messages.setOpenExternalLinks(True)

        input_row = QHBoxLayout()
        self.input = QLineEdit()
        self.input.setPlaceholderText("Напишите сообщение или нажмите микрофон...")

        self.mic_btn = QPushButton("Микрофон")
        self.send_btn = QPushButton("Отправить")

        input_row.addWidget(self.input)
        input_row.addWidget(self.mic_btn)
        input_row.addWidget(self.send_btn)

        quick_row = QHBoxLayout()
        quick_commands = [
            "Сколько свободной памяти?",
            "Открой браузер",
            "Найди файл",
            "Расскажи о системе",
            "Создай папку проекта",
        ]

        for cmd in quick_commands:
            btn = QPushButton(cmd)
            btn.clicked.connect(lambda checked=False, c=cmd: self._submit(c))
            quick_row.addWidget(btn)

        card_layout.addWidget(self.visual)
        card_layout.addWidget(self.status_label)
        card_layout.addWidget(self.messages, stretch=1)
        card_layout.addLayout(input_row)
        card_layout.addLayout(quick_row)

        right_layout.addWidget(card)

        splitter.addWidget(left)
        splitter.addWidget(right)
        splitter.setSizes([240, 900])

        root.addWidget(splitter)

        # Connections
        self.new_chat_btn.clicked.connect(self._new_chat)
        self.conv_list.currentItemChanged.connect(self._conversation_selected)
        self.send_btn.clicked.connect(self._submit_input)
        self.input.returnPressed.connect(self._submit_input)
        self.mic_btn.clicked.connect(self.orch.toggle_voice)

        self.orch.message_added.connect(self._on_message_added)
        self.orch.status_changed.connect(self.status_label.setText)
        self.orch.voice_state_changed.connect(self.visual.set_state)
        self.orch.conversations_changed.connect(self.refresh_conversations)

        self.refresh_conversations()
        self._load_conversation(self.orch.current_conversation)

    def refresh_conversations(self) -> None:
        self.conv_list.blockSignals(True)
        self.conv_list.clear()

        for conv in self.orch.get_conversations():
            item = QListWidgetItem(f"#{conv['id']} {conv['title']}")
            item.setData(Qt.ItemDataRole.UserRole, conv["id"])
            self.conv_list.addItem(item)

            if conv["id"] == self.orch.current_conversation:
                self.conv_list.setCurrentItem(item)

        self.conv_list.blockSignals(False)

    def _new_chat(self) -> None:
        self.orch.new_conversation()
        self.refresh_conversations()
        self._load_conversation(self.orch.current_conversation)

    def _conversation_selected(self, current, previous) -> None:
        if current is None:
            return
        conv_id = current.data(Qt.ItemDataRole.UserRole)
        self.orch.set_conversation(conv_id)
        self._load_conversation(conv_id)

    def _load_conversation(self, conversation_id: int) -> None:
        self.messages.clear()

        for msg in self.orch.get_messages(conversation_id):
            self._append_message(msg["role"], msg["content"])

    def _append_message(self, role: str, content: str) -> None:
        if role == "user":
            color = "#93c5fd"
            name = "Вы"
        elif role == "assistant":
            color = "#c4b5fd"
            name = "AURA"
        else:
            color = "#94a3b8"
            name = role

        self.messages.append(
            f"<p><b style='color:{color};'>{name}:</b></p>"
            f"<p>{html_escape(content)}</p>"
        )

    def _on_message_added(self, payload: dict) -> None:
        if payload.get("conversation_id") != self.orch.current_conversation:
            return
        self._append_message(payload["role"], payload["content"])

    def _submit_input(self) -> None:
        text = self.input.text().strip()
        if not text:
            return
        self.input.clear()
        self._submit(text)

    def _submit(self, text: str) -> None:
        self.orch.submit_text(text)


class MemoryWidget(QWidget):
    def __init__(self, orchestrator):
        super().__init__()
        self.orch = orchestrator

        layout = QVBoxLayout(self)

        top = QHBoxLayout()
        self.search = QLineEdit()
        self.search.setPlaceholderText("Поиск памяти...")
        self.search_btn = QPushButton("Найти")
        self.delete_btn = QPushButton("Удалить выбранное")
        top.addWidget(self.search)
        top.addWidget(self.search_btn)
        top.addWidget(self.delete_btn)

        self.table = QTableWidget(0, 4)
        self.table.setHorizontalHeaderLabels(["ID", "Категория", "Содержимое", "Дата"])
        self.table.horizontalHeader().setStretchLastSection(True)

        form = QFormLayout()
        self.category = QLineEdit("general")
        self.content = QLineEdit()
        self.add_btn = QPushButton("Добавить память")

        form.addRow("Категория", self.category)
        form.addRow("Содержимое", self.content)
        form.addRow("", self.add_btn)

        layout.addLayout(top)
        layout.addWidget(self.table, stretch=1)
        layout.addLayout(form)

        self.search_btn.clicked.connect(self.refresh)
        self.delete_btn.clicked.connect(self.delete_selected)
        self.add_btn.clicked.connect(self.add_memory)

        self.refresh()

    def refresh(self) -> None:
        query = self.search.text().strip()

        if query:
            result = self.orch.memory.search(query)
            rows = result.get("results", [])
        else:
            rows = self.orch.db.get_memories()

        self.table.setRowCount(len(rows))

        for i, row in enumerate(rows):
            self.table.setItem(i, 0, QTableWidgetItem(str(row["id"])))
            self.table.setItem(i, 1, QTableWidgetItem(row["category"]))
            self.table.setItem(i, 2, QTableWidgetItem(row["content"]))
            self.table.setItem(i, 3, QTableWidgetItem(row["created_at"]))

    def add_memory(self) -> None:
        self.orch.memory.save(self.category.text().strip(), self.content.text().strip())
        self.content.clear()
        self.refresh()

    def delete_selected(self) -> None:
        row = self.table.currentRow()
        if row < 0:
            QMessageBox.information(self, "Память", "Выберите запись для удаления.")
            return

        memory_id = int(self.table.item(row, 0).text())
        self.orch.db.delete_memory(memory_id)
        self.refresh()


class ActionsWidget(QWidget):
    def __init__(self, orchestrator):
        super().__init__()
        self.orch = orchestrator

        layout = QVBoxLayout(self)

        self.table = QTableWidget(0, 5)
        self.table.setHorizontalHeaderLabels(["Время", "Инструмент", "Статус", "Аргументы", "Результат"])
        self.table.horizontalHeader().setStretchLastSection(True)

        layout.addWidget(self.table)

        self.orch.action_logged.connect(self.append_action)
        self.refresh()

    def refresh(self) -> None:
        actions = self.orch.db.get_actions(limit=200)
        self.table.setRowCount(len(actions))

        for i, action in enumerate(actions):
            self.table.setItem(i, 0, QTableWidgetItem(action["created_at"]))
            self.table.setItem(i, 1, QTableWidgetItem(action["tool"]))
            self.table.setItem(i, 2, QTableWidgetItem(action["status"]))
            self.table.setItem(i, 3, QTableWidgetItem(json.dumps(action["args"], ensure_ascii=False)[:300]))
            self.table.setItem(i, 4, QTableWidgetItem(json.dumps(action["result"], ensure_ascii=False, default=str)[:500]))

    def append_action(self, payload: dict) -> None:
        row = 0
        self.table.insertRow(row)
        self.table.setItem(row, 0, QTableWidgetItem(payload.get("created_at", "")))
        self.table.setItem(row, 1, QTableWidgetItem(payload.get("tool", "")))
        self.table.setItem(row, 2, QTableWidgetItem(payload.get("status", "")))
        self.table.setItem(row, 3, QTableWidgetItem(json.dumps(payload.get("args", {}), ensure_ascii=False)[:300]))
        self.table.setItem(row, 4, QTableWidgetItem(json.dumps(payload.get("result", {}), ensure_ascii=False, default=str)[:500]))


class SettingsWidget(QWidget):
    def __init__(self, orchestrator):
        super().__init__()
        self.orch = orchestrator
        cfg = orchestrator.cfg

        layout = QVBoxLayout(self)

        form = QFormLayout()

        self.provider = QComboBox()
        self.provider.addItems(["openai", "groq", "ollama", "offline"])
        self.provider.setCurrentText(str(cfg.get("llm.provider", "openai")))

        self.base_url = QLineEdit(str(cfg.get("llm.base_url", "") or ""))
        self.model = QLineEdit(str(cfg.get("llm.model", "") or ""))

        self.temperature = QDoubleSpinBox()
        self.temperature.setRange(0.0, 2.0)
        self.temperature.setSingleStep(0.1)
        self.temperature.setValue(float(cfg.get("llm.temperature", 0.2) or 0.2))

        self.api_key = QLineEdit()
        self.api_key.setEchoMode(QLineEdit.EchoMode.Password)
        self.api_key.setPlaceholderText("Оставьте пустым, чтобы не менять текущий ключ")

        self.hotkey = QLineEdit(str(cfg.get("voice.hotkey", "<ctrl>+<alt>+<space>") or ""))
        self.continuous = QCheckBox()
        self.continuous.setChecked(bool(cfg.get("voice.continuous", False)))

        self.wake_enabled = QCheckBox()
        self.wake_enabled.setChecked(bool(cfg.get("voice.wake_enabled", False)))
        self.wake_phrase = QLineEdit(str(cfg.get("voice.wake_phrase", "аура") or ""))

        self.stt_model = QComboBox()
        self.stt_model.addItems(["tiny", "base", "small", "medium", "large-v3"])
        self.stt_model.setCurrentText(str(cfg.get("stt.model", "small")))

        self.stt_device = QComboBox()
        self.stt_device.addItems(["auto", "cuda", "cpu"])
        self.stt_device.setCurrentText(str(cfg.get("stt.device", "auto")))

        self.tts_enabled = QCheckBox()
        self.tts_enabled.setChecked(bool(cfg.get("tts.enabled", True)))

        self.tts_engine = QComboBox()
        self.tts_engine.addItems(["edge", "pyttsx3"])
        self.tts_engine.setCurrentText(str(cfg.get("tts.engine", "edge")))

        self.tts_voice = QLineEdit(str(cfg.get("tts.voice", "ru-RU-SvetlanaNeural") or ""))
        self.tts_edge_rate = QLineEdit(str(cfg.get("tts.edge_rate", "+0%") or "+0%"))

        self.computer_control = QCheckBox()
        self.computer_control.setChecked(bool(cfg.get("safety.computer_control_enabled", True)))

        self.require_confirmation = QCheckBox()
        self.require_confirmation.setChecked(bool(cfg.get("safety.require_confirmation", True)))

        form.addRow("LLM провайдер", self.provider)
        form.addRow("Base URL (опционально)", self.base_url)
        form.addRow("Модель", self.model)
        form.addRow("Temperature", self.temperature)
        form.addRow("API ключ", self.api_key)
        form.addRow("Горячая клавиша", self.hotkey)
        form.addRow("Непрерывное общение", self.continuous)
        form.addRow("Wake word включён", self.wake_enabled)
        form.addRow("Фраза активации", self.wake_phrase)
        form.addRow("Whisper модель", self.stt_model)
        form.addRow("Whisper устройство", self.stt_device)
        form.addRow("Озвучка включена", self.tts_enabled)
        form.addRow("TTS движок", self.tts_engine)
        form.addRow("TTS голос", self.tts_voice)
        form.addRow("TTS темп (Edge)", self.tts_edge_rate)
        form.addRow("Управление компьютером", self.computer_control)
        form.addRow("Подтверждать опасные действия", self.require_confirmation)

        buttons = QHBoxLayout()
        self.save_btn = QPushButton("Сохранить")
        self.test_tts_btn = QPushButton("Проверить голос")
        buttons.addWidget(self.save_btn)
        buttons.addWidget(self.test_tts_btn)

        self.note = QLabel(
            "API-ключи хранятся в Windows Credential Manager. "
            "Для GPU в Whisper может потребоваться установка CUDA-зависимостей. "
            "Если Wake Word не работает, используйте горячую клавишу или непрерывный режим."
        )
        self.note.setWordWrap(True)
        self.note.setObjectName("SubtitleLabel")

        layout.addLayout(form)
        layout.addLayout(buttons)
        layout.addWidget(self.note)
        layout.addStretch(1)

        self.save_btn.clicked.connect(self.save)
        self.test_tts_btn.clicked.connect(lambda: self.orch.speaker.speak("Проверка голоса AURA."))
        self.provider.currentTextChanged.connect(self._update_key_placeholder)

        self._update_key_placeholder()

    def _update_key_placeholder(self) -> None:
        provider = self.provider.currentText()
        if provider in ("openai", "groq"):
            current = get_secret(f"{provider}_api_key")
            masked = "задан" if current else "не задан"
            self.api_key.setPlaceholderText(f"Текущий ключ {provider}: {masked}")
        else:
            self.api_key.setPlaceholderText("Для этого провайдера ключ не требуется")

    def save(self) -> None:
        cfg = self.orch.cfg

        provider = self.provider.currentText()
        api_key = self.api_key.text().strip()

        cfg.set("llm.provider", provider)
        cfg.set("llm.base_url", self.base_url.text().strip())
        cfg.set("llm.model", self.model.text().strip())
        cfg.set("llm.temperature", self.temperature.value())

        if provider in ("openai", "groq") and api_key:
            set_secret(f"{provider}_api_key", api_key)

        cfg.set("voice.hotkey", self.hotkey.text().strip())
        cfg.set("voice.continuous", self.continuous.isChecked())
        cfg.set("voice.wake_enabled", self.wake_enabled.isChecked())
        cfg.set("voice.wake_phrase", self.wake_phrase.text().strip())

        cfg.set("stt.model", self.stt_model.currentText())
        cfg.set("stt.device", self.stt_device.currentText())

        cfg.set("tts.enabled", self.tts_enabled.isChecked())
        cfg.set("tts.engine", self.tts_engine.currentText())
        cfg.set("tts.voice", self.tts_voice.text().strip())
        cfg.set("tts.edge_rate", self.tts_edge_rate.text().strip())

        cfg.set("safety.computer_control_enabled", self.computer_control.isChecked())
        cfg.set("safety.require_confirmation", self.require_confirmation.isChecked())

        cfg.save()

        self.orch.reload_llm()
        self.orch.reload_stt()
        self.orch.reload_hotkey()

        QMessageBox.information(
            self,
            "Настройки",
            "Настройки сохранены. Часть параметров вступает в силу немедленно, "
            "но для изменения горячих клавиш и TTS/STT может потребоваться перезапуск приложения.",
        )
