from __future__ import annotations

import time

from PySide6.QtCore import Qt, QTimer
from PySide6.QtWidgets import (
    QButtonGroup,
    QFrame,
    QHBoxLayout,
    QInputDialog,
    QLabel,
    QListWidget,
    QListWidgetItem,
    QMessageBox,
    QPushButton,
    QSplitter,
    QVBoxLayout,
    QWidget,
)

from .widgets import ChatWidget


MODE_LABELS = {
    "normal": "Обычный",
    "agent": "Agent",
    "vision": "Vision",
}


class DashboardWidget(QWidget):
    """NOVA-inspired dashboard with assistant modes, chat, tasks and activity."""

    def __init__(self, orchestrator):
        super().__init__()
        self.orch = orchestrator
        self.session_started = time.monotonic()

        root = QVBoxLayout(self)
        root.setContentsMargins(18, 16, 18, 16)
        root.setSpacing(12)

        header = QHBoxLayout()
        title_col = QVBoxLayout()
        title = QLabel("JARVIS CONTROL CENTER")
        title.setObjectName("SectionTitle")
        subtitle = QLabel("Голосовой помощник · локальное управление · AI-агент")
        subtitle.setObjectName("SubtitleLabel")
        title_col.addWidget(title)
        title_col.addWidget(subtitle)
        header.addLayout(title_col, 1)

        self.session_label = QLabel("СЕССИЯ 00:00")
        self.session_label.setObjectName("CommandSummary")
        self.session_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        header.addWidget(self.session_label)
        root.addLayout(header)

        mode_card = QFrame()
        mode_card.setObjectName("Card")
        mode_layout = QHBoxLayout(mode_card)
        mode_layout.addWidget(QLabel("РЕЖИМ РАБОТЫ"))
        self.mode_group = QButtonGroup(self)
        self.mode_group.setExclusive(True)
        self.mode_buttons = {}
        for mode, label in MODE_LABELS.items():
            button = QPushButton(label)
            button.setCheckable(True)
            button.setMinimumHeight(38)
            self.mode_group.addButton(button)
            self.mode_buttons[mode] = button
            mode_layout.addWidget(button)
        mode_layout.addStretch(1)
        self.mode_hint = QLabel("Команды выполняются напрямую; сложные запросы передаются ИИ.")
        self.mode_hint.setObjectName("SubtitleLabel")
        self.mode_hint.setWordWrap(True)
        mode_layout.addWidget(self.mode_hint, 2)
        root.addWidget(mode_card)

        stats = QHBoxLayout()
        self.provider_label = self._stat_card("AI-ПРОВАЙДЕР", "—")
        self.commands_label = self._stat_card("БИБЛИОТЕКА", "—")
        self.state_label = self._stat_card("СОСТОЯНИЕ", "Готов")
        for card in (self.provider_label, self.commands_label, self.state_label):
            stats.addWidget(card, 1)
        root.addLayout(stats)

        splitter = QSplitter(Qt.Orientation.Horizontal)
        self.chat = ChatWidget(orchestrator)
        splitter.addWidget(self.chat)

        side = QWidget()
        side_layout = QVBoxLayout(side)
        side_layout.setContentsMargins(0, 0, 0, 0)
        side_layout.setSpacing(10)

        tasks_header = QHBoxLayout()
        tasks_header.addWidget(QLabel("МОИ ЗАДАЧИ"), 1)
        self.add_task_btn = QPushButton("+ Добавить")
        tasks_header.addWidget(self.add_task_btn)
        side_layout.addLayout(tasks_header)
        self.tasks = QListWidget()
        self.tasks.setMinimumHeight(160)
        side_layout.addWidget(self.tasks, 2)

        activity_header = QHBoxLayout()
        activity_header.addWidget(QLabel("ПОСЛЕДНИЕ СОБЫТИЯ"), 1)
        self.refresh_btn = QPushButton("↻")
        self.refresh_btn.setMaximumWidth(40)
        activity_header.addWidget(self.refresh_btn)
        side_layout.addLayout(activity_header)
        self.activity = QListWidget()
        self.activity.setMinimumHeight(180)
        side_layout.addWidget(self.activity, 3)

        self.notice = QLabel(
            "Agent выполняет цепочки инструментов. Vision анализирует снимок экрана "
            "через выбранную AI-модель после отдельного разрешения."
        )
        self.notice.setObjectName("SubtitleLabel")
        self.notice.setWordWrap(True)
        side_layout.addWidget(self.notice)
        splitter.addWidget(side)
        splitter.setSizes([760, 320])
        splitter.setStretchFactor(0, 3)
        splitter.setStretchFactor(1, 1)
        root.addWidget(splitter, 1)

        self.mode_buttons["normal"].clicked.connect(lambda: self.change_mode("normal"))
        self.mode_buttons["agent"].clicked.connect(lambda: self.change_mode("agent"))
        self.mode_buttons["vision"].clicked.connect(lambda: self.change_mode("vision"))
        self.add_task_btn.clicked.connect(self.add_task)
        self.refresh_btn.clicked.connect(self.refresh_panels)
        self.orch.status_changed.connect(self._on_status)
        self.orch.action_logged.connect(lambda _payload: self.refresh_activity())

        self.timer = QTimer(self)
        self.timer.setInterval(1000)
        self.timer.timeout.connect(self._update_session)
        self.timer.start()

        initial = str(getattr(self.orch, "mode", "normal"))
        self.mode_buttons.get(initial, self.mode_buttons["normal"]).setChecked(True)
        self._set_mode_hint(initial)
        self._update_session()
        self.refresh_panels()
        self._refresh_stats()

    def _stat_card(self, title: str, value: str) -> QFrame:
        card = QFrame()
        card.setObjectName("Card")
        layout = QVBoxLayout(card)
        layout.setContentsMargins(12, 8, 12, 8)
        heading = QLabel(title)
        heading.setObjectName("SubtitleLabel")
        value_label = QLabel(value)
        value_label.setObjectName("CommandSummary")
        layout.addWidget(heading)
        layout.addWidget(value_label)
        card.value_label = value_label
        return card

    def _update_session(self) -> None:
        seconds = int(time.monotonic() - self.session_started)
        hours, rem = divmod(seconds, 3600)
        minutes, seconds = divmod(rem, 60)
        self.session_label.setText(f"СЕССИЯ {hours:02}:{minutes:02}:{seconds:02}")

    def _refresh_stats(self) -> None:
        self.provider_label.value_label.setText(str(getattr(self.orch.llm, "name", "не настроен")))
        counts = self.orch.jarvis_commands.counts()
        self.commands_label.value_label.setText(
            f"{counts['ready']} готовы · {counts['setup']} настройка · {counts['planned']} в плане"
        )

    def _on_status(self, status: str) -> None:
        self.state_label.value_label.setText(str(status)[:90])
        self._refresh_stats()

    def _set_mode_hint(self, mode: str) -> None:
        descriptions = {
            "normal": "Системные фразы исполняются локально; свободные запросы идут в ИИ.",
            "agent": "Агент может выполнять многошаговые задачи через доступные инструменты. Рискованные действия требуют подтверждения.",
            "vision": "Vision анализирует текущий снимок экрана. Содержимое снимка передаётся выбранному AI-провайдеру.",
        }
        self.mode_hint.setText(descriptions.get(mode, descriptions["normal"]))

    def change_mode(self, mode: str) -> None:
        previous = str(getattr(self.orch, "mode", "normal"))
        if mode == "vision":
            reply = QMessageBox.question(
                self,
                "Разрешение Vision",
                "Для каждого запроса в режиме Vision JARVIS сделает снимок всех экранов "
                "и отправит его выбранному AI-провайдеру вместе с вопросом. "
                "На изображении могут быть видны личные сообщения, документы или другие данные.\n\n"
                "Разрешить использование снимков экрана, пока включён режим Vision?",
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
                QMessageBox.StandardButton.No,
            )
            if reply != QMessageBox.StandardButton.Yes:
                self.mode_buttons.get(previous, self.mode_buttons["normal"]).setChecked(True)
                return
            self.orch.set_mode("vision", authorized=True)
        else:
            self.orch.set_mode(mode)
        self.mode_buttons[mode].setChecked(True)
        self._set_mode_hint(mode)

    def add_task(self) -> None:
        text, accepted = QInputDialog.getText(self, "Новая задача", "Что нужно сделать?")
        text = text.strip()
        if not accepted or not text:
            return
        self.orch.db.add_memory("task", text)
        self.refresh_tasks()

    def refresh_tasks(self) -> None:
        self.tasks.clear()
        for row in self.orch.db.get_memories():
            if str(row.get("category", "")).casefold() == "task":
                item = QListWidgetItem(str(row.get("content", "")))
                item.setData(Qt.ItemDataRole.UserRole, row.get("id"))
                self.tasks.addItem(item)

    def refresh_activity(self) -> None:
        self.activity.clear()
        for row in self.orch.db.get_actions(limit=12):
            status = "✓" if row.get("status") == "success" else "•"
            tool = str(row.get("tool", "action"))
            created = str(row.get("created_at", ""))[-8:]
            self.activity.addItem(f"{status} {created}  {tool}")

    def refresh_panels(self) -> None:
        self.refresh_tasks()
        self.refresh_activity()
        self._refresh_stats()
